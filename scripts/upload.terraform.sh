#!/bin/bash
set -euo pipefail
shopt -s extglob nocasematch

: "${SOURCE_PATH:?}"
: "${ARTIFACT_BUCKET:?}"
: "${ARTIFACT_PREFIX:=""}"
: "${SIGNING_KMS_KEY_ARN:=""}"
: "${HEAD_MESSAGE:=$(git log -1 --format=%s)}"
: "${COMMIT_MESSAGES:=}"
: "${COMMIT_SHA:=$(git rev-parse HEAD)}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_TOKEN:=}"
: "${TF_MODULE_PATH:=}"

[[ ${ARTIFACT_PREFIX:-} ]] && s3_prefix=${ARTIFACT_PREFIX%%+(/)}/

function check_directory_exists() {
  local directory=$1
  if ! [[ -d $directory ]]; then
    echo "Error: Directory $directory not found" >&2
    exit 1
  fi
}

echo "::group::Downloading Terraform module dependencies"
echo "» Checking Terraform root directory exists"

if [[ $GITHUB_TOKEN ]]; then
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/govuk-one-login".insteadOf "ssh://git@github.com/govuk-one-login"
fi

while IFS= read -r module_path; do
  [[ -z "$module_path" ]] && continue
  check_directory_exists "$module_path"
  echo "» Running terraform get in $module_path"
  terraform -chdir="${module_path}" get
done <<< "$TF_MODULE_PATH"

echo "» Terraform modules downloaded"
echo "::endgroup::"

echo "» Checking source path exists"
check_directory_exists "$SOURCE_PATH"

SERVICE_ZIP_NAME="service.zip"
SERVICE_ZIP_PATH="$GITHUB_WORKSPACE/$SERVICE_ZIP_NAME"
zip -r "$SERVICE_ZIP_PATH" "$SOURCE_PATH"

ZIPSUM_FILE="zipsum.txt"
SIGNATURE_FILE="ZipSignature"
PACKAGE_FILE="package.zip"
md5sum "$SERVICE_ZIP_PATH" | cut -c -32 > $ZIPSUM_FILE

if [[ -n "$SIGNING_KMS_KEY_ARN" ]]; then
  aws kms sign \
    --key-id "$SIGNING_KMS_KEY_ARN" \
    --message fileb://"$ZIPSUM_FILE" \
    --signing-algorithm RSASSA_PSS_SHA_256 \
    --message-type RAW \
    --output text \
    --query Signature | base64 --decode > $SIGNATURE_FILE
else
  echo "No SIGNING_KMS_KEY_ARN provided, skipping signing step."
  touch $SIGNATURE_FILE
fi
zip -r $PACKAGE_FILE "$SERVICE_ZIP_NAME" "$SIGNATURE_FILE"

if [[ $COMMIT_MESSAGES =~ \[(auto[ -]approve[ -]all|skip[ -]approval)\] ]]; then
  skip_approval=true
  skip_envs=""
else
  skip_approval=false
  if env=$(echo "$COMMIT_MESSAGES" | grep -oP "(auto[ -]approve|skip[ -]approval)[ -]\K[^] ]+"); then
    skip_envs=$(echo "$env" | tr '\n' ',' | sed 's/,$//')
  else
    skip_envs=""
  fi
fi
COMMIT_MESSAGE=$(echo "${HEAD_MESSAGE}" | tr '[]' '()' | tr '\n' ' ' | tr ',' ';' | tr -d '"' | head -n 1 | cut -c1-50 | xargs)
METADATA="repository=$GITHUB_REPOSITORY,commitsha=$COMMIT_SHA,commitmessage=$COMMIT_MESSAGE,skipapproval=${skip_approval:-false}"
if [ -n "$skip_envs" ]; then
  METADATA="$METADATA,skipapprovalenvs='$skip_envs'"
fi
aws s3 cp $PACKAGE_FILE "s3://${ARTIFACT_BUCKET}/${s3_prefix:-}$PACKAGE_FILE" --metadata "${METADATA}"
aws s3 cp $ZIPSUM_FILE "s3://${ARTIFACT_BUCKET}/${s3_prefix:-}$ZIPSUM_FILE" --metadata "${METADATA}"
