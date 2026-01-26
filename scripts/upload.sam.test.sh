#!/usr/bin/env bash
set -euo pipefail

source scripts/utility.test.sh

uri_regex="^s3:\/\/${ARTIFACT_BUCKET}\/${ARTIFACT_PREFIX:-}"

function verify-lambda-uri() {
  local uri=$1
  echo "» Verifying URI for $name"
  [[ $uri =~ $uri_regex ]] || report-error "URI doesn't match \`/$uri_regex/\`" <<< "$uri"
}

function verify-lambda() {
  local name=$1 uri
  uri=$(yq --exit-status ".Resources.${name}.Properties | .CodeUri // .ContentUri" "$TEMPLATE_FILE" 2>&1) ||
    report-error "Could not retrieve URI" <<< "$uri" || return 1

  verify-lambda-uri "$uri" || return 1
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
