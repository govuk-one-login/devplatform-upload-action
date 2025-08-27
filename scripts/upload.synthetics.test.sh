#!/usr/bin/env bash
set -euo pipefail

source scripts/utility.test.sh

function verify-synthetics-canary-version() {
  local key=$1 version=$2
  echo "» Verifying S3 version for $name"

  uploaded_version=$(aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$key" --query VersionId --output text 2>&1) ||
    report-error "VersionId could not be retrieved" <<< "$uploaded_version"

  [[ $version =~ $uploaded_version ]] || report-error "S3ObjectVersion in the template doesn't match head object VersionID" <<< "$version $uploaded_version"
}

function verify-synthetics-canary() {
  local name=$1 key
  key=$(yq --exit-status ".Resources.${name}.Properties | .Code.S3Key" "$TEMPLATE_FILE" 2>&1) ||
    report-error "Could not retrieve S3 key" <<< "$key" || return 1

  version=$(yq --exit-status ".Resources.${name}.Properties | .Code.S3ObjectVersion" "$TEMPLATE_FILE" 2>&1) ||
    report-error "Could not retrieve S3 version" <<< "$version" || return 1

  verify-synthetics-canary-version "$key" "$version" || return 1
  verify-object-metadata "$key" || return 1
}

function get-synthetics-canary-names() {
  local synthetics_canary_result
  synthetics_canary_result=$(yq --exit-status \
    '.Resources[] | select(
      .Type=="AWS::Synthetics::Canary"
    ) | key' "$TEMPLATE_FILE" 2>&1) ||
    report-error "Error getting synthetics canary names from template" <<< "$synthetics_canary_result" || return 1

  mapfile -t synthetics_canaries <<< "$synthetics_canary_result"
  [[ ${#synthetics_canaries[@]} -gt 0 ]] || report-error "No synthetics canaries found in the template" <<< "$synthetics_canary_result"
}

failed=false
get-synthetics-canary-names

for synthetics_canary in "${synthetics_canaries[@]}"; do
  verify-synthetics-canary "$synthetics_canary" || failed=true
done

$failed && exit 1
echo "✅ All checks have passed"
