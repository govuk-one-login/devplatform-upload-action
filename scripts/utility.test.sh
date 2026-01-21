#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${ARTIFACT_PREFIX:-}"

: "${VERSION:=}"
: "${SKIP_CANARY:=0}"
: "${CLOSE_CIRCUIT_BREAKER:=0}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"
: "${GIT_TAG:=$(git describe --tags --first-parent --always)}"
: "${COMMIT_MESSAGE:=$(git log -1 --format=%s | head -n 1 | cut -c1-50 | xargs)}"
: "${MERGE_TS:=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")}"

: "${TEMPLATE_FILE:=cf-template.yaml}"
: "${RESULTS_FILE:=${GITHUB_STEP_SUMMARY:-results}}"

rm -f "$RESULTS_FILE"
declare -A expected_metadata

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
  [closecircuitbreaker]=$CLOSE_CIRCUIT_BREAKER
)

function format-error() {
  local heading=$1
  echo "$heading"
  echo
  cat "${@:2}"
  echo
  return 1
}

function object-message() {
  local message=$1
  echo "${message}${name:+ for \`$name\`}${key:+ at \`$key\`}"
}

function write-error() {
  format-error "#### 🆇 $(object-message "$1")" "${@:2}" >> "$RESULTS_FILE"
}

function print-error() {
  format-error "::error::$(object-message "$1" | tr -d '`')" "${@:2}" >&2
}

function report-error() {
  tee >(print-error "$@") | write-error "$@" <(echo '```') - <(echo '```')
}

function invalid-result() {
  local IFS="|" && echo "|$*|"
}

function add-invalid-result() {
  invalid_results+=("$(invalid-result "$@")")
}

function expand-invalid-results() {
  invalid-result Key Expected Actual
  invalid-result - - -
  local IFS=$'\n' && echo "${invalid_results[*]}"
}

function print-invalid-results() {
  sed "s/||/| |/g" | column -ts "|" | print-error "$@"
}

function validate-results() {
  [[ ${#invalid_results[@]} -eq 0 ]] ||
    expand-invalid-results | tee >(write-error "$@") | print-invalid-results "$@"
}

function get-object-metadata() {
  metadata=$(aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$key" --query Metadata 2>&1) ||
    report-error "Metadata could not be retrieved" <<< "$metadata"
}

function verify-object-metadata() {
  local key=$1 name=${2:-$name} invalid_results=() metadata meta expected actual

  echo "» Verifying metadata for $name"
  get-object-metadata || return 1

  for meta in "${!expected_metadata[@]}"; do
    expected=${expected_metadata[$meta]}
    actual=$(jq --raw-output --arg key "$meta" '.[$key] // empty' <<< "$metadata")
    [[ $expected == "$actual" ]] || add-invalid-result "\`$meta\`" "$expected" "$actual"
  done

  validate-results "Invalid metadata"
}

function verify-terraform-zip-contents() {
  local s3_key=$1
  local local_zip="downloaded_package.zip"

  echo "🔎 Verifying internal dependencies for $s3_key..."
  aws s3 cp "s3://$ARTIFACT_BUCKET/$s3_key" "$local_zip"

  echo "📦 Checking zip file for service.zip"
  if ! unzip -l "$local_zip" | grep -q "service.zip"; then
    report-error "Missing service.zip in package"
    return 1
  fi

  echo "📦 Checking zip file for ZipSignature"
  if ! unzip -l "$local_zip" | grep -q "ZipSignature"; then
    report-error "Missing ZipSignature file in package"
    return 1
  fi

  unzip -p "$local_zip" service.zip > nested_service.zip

  echo "📦 Checking zip file for .terraform/modules"
  if ! unzip -l nested_service.zip | grep -q ".terraform/modules/"; then
    report-error "Error: .terraform/modules directory missing in service.zip"
    return 1
  fi

  echo "📦 Checking zip file for modules.json"
  if ! unzip -l nested_service.zip | grep -q ".terraform/modules/modules.json"; then
    report-error "Error: .terraform/modules directory missing in service.zip"
    return 1
  fi

  echo "📦 Checking 'terraform get' dependencies"
  manifest=$(unzip -p nested_service.zip "*/.terraform/modules/modules.json")
  if [[ -z "$manifest" ]]; then
    report-error "Error: Could not extract content from modules.json"
    return 1
  fi

  if echo "$manifest" | grep -q "my_test_dependency"; then
    echo "✅ Success: 'terraform get' successfully mapped 'my_test_dependency'"
  else
    echo "❌ Error: 'my_test_dependency' not found in modules.json"
    exit 1
  fi

  echo "📦 Checking zip file for main.tf"
  if ! unzip -l nested_service.zip | grep -q "main.tf"; then
    report-error "Error: main.tf not found inside .terraform/modules in service.zip"
    return 1
  fi

  echo "✅ All internal zip requirements met."
}

function verify-terraform-zipsum() {
  local s3_zipsum=$1

  if aws s3 ls "$s3_zipsum" > /dev/null 2>&1; then
    echo "✅ Success: zipsum.txt found on S3."
  else
    echo "❌ Error: zipsum.txt is missing from S3!"
    exit 1
  fi
}
