#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${ARTIFACT_PREFIX:-}"

: "${VERSION:=}"
: "${SKIP_CANARY:=0}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"
: "${GIT_TAG:=$(git describe --tags --first-parent --always)}"
: "${COMMIT_MESSAGE:=$(git log -1 --format=%s | head -n 1 | cut -c1-50)}"
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

function verify-lambda() {
  local name=$1 uri
  uri=$(yq --exit-status ".Resources.${name}.Properties | .CodeUri // .ContentUri" "$TEMPLATE_FILE" 2>&1) ||
    report-error "Could not retrieve URI" <<< "$uri" || return 1

  verify-object-metadata "${uri#s3://*/}"
}

function get-lambda-names() {
  local lambdas_result
  lambdas_result=$(yq --exit-status \
    '.Resources[] | select(
      .Type=="AWS::Serverless::Function" or
      .Type=="AWS::Serverless::LayerVersion"
    ) | key' "$TEMPLATE_FILE" 2>&1) ||
    report-error "Error getting lambda names from template" <<< "$lambdas_result" || return 1

  mapfile -t lambdas <<< "$lambdas_result"
  [[ ${#lambdas[@]} -gt 0 ]] || report-error "No lambdas found in the template" <<< "$lambdas_result"
}

failed=false
get-lambda-names

verify-object-metadata "${ARTIFACT_PREFIX:+$ARTIFACT_PREFIX/}template.zip" template || failed=true

for lambda in "${lambdas[@]}"; do
  verify-lambda "$lambda" || failed=true
done

$failed && exit 1
echo "✅ All checks have passed"
