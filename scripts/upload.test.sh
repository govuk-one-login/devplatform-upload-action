#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${SKIP_CANARY:=0}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"
: "${GIT_TAG:=$(git describe --tags --first-parent --always)}"
: "${COMMIT_MESSAGE:=$(git log -1 --format=%s | head -n 1 | cut -c1-50)}"
: "${MERGE_TS:=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")}"

: "${TEMPLATE_FILE:=cf-template.yaml}"
: "${RESULTS_FILE:=${GITHUB_STEP_SUMMARY:-results}}"

declare -A expected_metadata

function report-error() {
  tee -a "$RESULTS_FILE"
  failed=true
}

function print-metadata-results() {
  local name=$1
  echo "#### ❌ Invalid metadata for \`$name\`"
  echo '```'
  column -ts $'\t' < <(invalid-metadata-entry "[Key]" "[Expected]" "[Actual]" && cat)
  echo '```'
}

function invalid-metadata-entry() {
  local key=$1 expected=$2 actual=$3 entry
  entry=("$key" "$expected" "$actual")
  (IFS=$'\t' && echo "${entry[*]}")
}

function get-object-metadata() {
  local object_key=$1
  aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$object_key" --query Metadata
}

function verify-object-metadata() {
  local object_key=$1 invalid_metadata=() metadata key expected actual
  metadata=$(get-object-metadata "$object_key")

  for key in "${!expected_metadata[@]}"; do
    expected=${expected_metadata[$key]}
    actual=$(jq --raw-output --arg key "$key" '.[$key]' <<< "$metadata")
    [[ $expected == "$actual" ]] || invalid_metadata+=("$(invalid-metadata-entry "$key" "$expected" "$actual")")
  done

  if [[ ${#invalid_metadata[@]} -gt 0 ]]; then
    print-metadata-results "$object_key" < <(IFS=$'\n' && echo "${invalid_metadata[*]}")
    return 1
  fi
}

expected_metadata=(
  [commitsha]=$GITHUB_SHA
  [committag]=$GIT_TAG
  [commitmessage]=$COMMIT_MESSAGE
  [mergetime]=$MERGE_TS
  [commitauthor]=$GITHUB_ACTOR
  [repository]=$GITHUB_REPOSITORY
  [skipcanary]=$SKIP_CANARY
)

failed=false
rm -f "$RESULTS_FILE"

metadata_results=$(verify-object-metadata template.zip) || report-error <<< "$metadata_results"
metadata_results=$(verify-object-metadata template.zip) || report-error <<< "$metadata_results"

$failed && exit 1
echo "✅ All checks have passed"
