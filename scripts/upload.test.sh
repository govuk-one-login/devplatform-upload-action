#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${VERSION:=null}"
: "${SKIP_CANARY:=0}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"
: "${GIT_TAG:=$(git describe --tags --first-parent --always)}"
: "${COMMIT_MESSAGE:=$(git log -1 --format=%s | head -n 1 | cut -c1-50)}"
: "${MERGE_TS:=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")}"

: "${TEMPLATE_FILE:=cf-template.yaml}"
: "${RESULTS_FILE:=${GITHUB_STEP_SUMMARY:-results}}"

rm -f "$RESULTS_FILE"
declare -A expected_metadata

function report-error() {
  local heading=$1
  {
    echo "#### ❌ $heading"
    echo '```'
    cat
    echo '```'
  } | tee -a "$RESULTS_FILE"
}

function get-lambdas() {
  yq '.Resources[] | select(
        .Type=="AWS::Serverless::Function" or
        .Type=="AWS::Serverless::LayerVersion"
      ) | key' "$TEMPLATE_FILE"
}

function invalid-metadata-entry() {
  local key=$1 expected=$2 actual=$3 entry
  entry=("$key" "$expected" "$actual")
  (IFS=$'\t' && echo "${entry[*]}")
}

function print-metadata-results() {
  {
    invalid-metadata-entry "[Key]" "[Expected]" "[Actual]"
    IFS=$'\n' && echo "${invalid_metadata[*]}"
  } | column -ts $'\t'
}

function get-object-metadata() {
  metadata=$(aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$key" --query Metadata 2>&1) && return
  report-error "Metadata could not be retrieved for \`${name:-$key}\`" <<< "$metadata"
  return 1
}

function verify-object-metadata() {
  local key=$1 name=${2:-} invalid_metadata=() metadata key expected actual

  echo "Verifying metadata for ${name:-$key}"
  get-object-metadata "$key" || return 1

  for key in "${!expected_metadata[@]}"; do
    expected=${expected_metadata[$key]}
    actual=$(jq --raw-output --arg key "$key" '.[$key]' <<< "$metadata")
    [[ $expected == "$actual" ]] || invalid_metadata+=("$(invalid-metadata-entry "$key" "$expected" "$actual")")
  done

  if [[ ${#invalid_metadata[@]} -gt 0 ]]; then
    print-metadata-results | report-error "Invalid metadata for \`${name:-$key}\`"
    return 1
  fi
}

function verify-lambda() {
  local name=$1 uri
  uri=$(yq ".Resources.${lambda}.Properties | .CodeUri // .ContentUri" "$TEMPLATE_FILE")
  verify-object-metadata "${uri##*/}" "$name"
}

expected_metadata=(
  [commitsha]=$GITHUB_SHA
  [committag]=$GIT_TAG
  [commitmessage]=$COMMIT_MESSAGE
  [mergetime]=$MERGE_TS
  [commitauthor]=$GITHUB_ACTOR
  [repository]=$GITHUB_REPOSITORY
  [skipcanary]=$SKIP_CANARY
  [release]=$VERSION
  ["codepipeline-artifact-revision-summary"]=$VERSION
)

failed=false
lambdas=$(get-lambdas)

verify-object-metadata template.zip || failed=true

for lambda in $lambdas; do
  verify-lambda "$lambda" || failed=true
done

$failed && exit 1
echo "✅ All checks have passed"
