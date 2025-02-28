#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${VERSION:=null}"
: "${SKIP_CANARY:=0}"
: "${SIGNING_PROFILE:-}"
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

function metadata-entry() {
  local IFS=$'\t' && echo "$*"
}

function print-metadata-results() {
  {
    metadata-entry "[Key]" "[Expected]" "[Actual]"
    IFS=$'\n' && echo "${invalid_metadata[*]}"
  } | column -ts $'\t'
}

function get-object-metadata() {
  metadata=$(aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$object_key" --query Metadata 2>&1) && return
  report-error "Metadata could not be retrieved for \`$object_key${name:+ ($name)}\`" <<< "$metadata"
  return 1
}

function verify-object-metadata() {
  local object_key=$1 name=${2:-} invalid_metadata=() metadata key expected actual

  echo "Verifying metadata for ${name:-$object_key}"
  get-object-metadata || return 1

  for key in "${!expected_metadata[@]}"; do
    expected=${expected_metadata[$key]}
    actual=$(jq --raw-output --arg key "$key" '.[$key]' <<< "$metadata")
    [[ $expected == "$actual" ]] || invalid_metadata+=("$(metadata-entry "$key" "$expected" "$actual")")
  done

  if [[ ${#invalid_metadata[@]} -gt 0 ]]; then
    print-metadata-results | report-error "Invalid metadata for \`$object_key${name:+ ($name)}\`"
    return 1
  fi
}

function verify-object-signed() {
  local key=$1
  jq '.jobs[] select()' <<< "$signing_jobs"
}

function verify-lambda() {
  local name=$1 uri
  uri=$(yq ".Resources.${lambda}.Properties | .CodeUri // .ContentUri" "$TEMPLATE_FILE")
  verify-object-metadata "${uri#s3://*/}" "$name"
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
mapfile -t lambdas < <(get-lambdas)

if [[ ${SIGNING_PROFILE:-} ]]; then
  aws_identity=$(aws sts get-caller-aws_identity --query Arn --output text)
  signing_jobs=$(aws signer list-signing-jobs --requested-by "$aws_identity" --max-items $((${#lambdas[@]} * 10)))
fi

verify-object-metadata template.zip || failed=true

for lambda in "${lambdas[@]}"; do
  verify-lambda "$lambda" || failed=true
done

$failed && exit 1
echo "✅ All checks have passed"
