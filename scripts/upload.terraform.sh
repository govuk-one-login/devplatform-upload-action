#!/bin/bash
set -euo pipefail
shopt -s extglob nocasematch

: "${WORKING_DIRECTORY:?}"
: "${ARTIFACT_BUCKET:?}"
: "${ARTIFACT_PREFIX:=""}"
: "${SIGNING_PROFILE:=""}"
: "${HEAD_MESSAGE:=$(git log -1 --format=%s)}"
: "${COMMIT_MESSAGES:=}"
: "${COMMIT_SHA:=$(git rev-parse HEAD)}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_TOKEN:=}"
: "${TERRAFORM_ROOT:=}"

[[ ${ARTIFACT_PREFIX:-} ]] && s3_prefix=${ARTIFACT_PREFIX%%+(/)}/

function check_directory() {
  local directory=${1}
  if [ ! -d "$directory" ]; then
    echo "Error: Directory $directory not found." >&2
    exit 1
  fi
}

cd "$GITHUB_WORKSPACE"

echo "» Checking working-directory"
check_directory "$WORKING_DIRECTORY"

if [[ -n "$GITHUB_TOKEN" ]]; then
  echo "::group::Downloading Terraform modules"
  echo "» Checking terraform-root"
  check_directory "$TERRAFORM_ROOT"

  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/govuk-one-login".insteadOf "ssh://git@github.com/govuk-one-login"
  terraform -chdir="${TERRAFORM_ROOT}" get

  echo "» Terraform modules downloaded"
  echo "::endgroup::"
fi

echo "» Checking working-directory"
check_directory "$WORKING_DIRECTORY"
cd "$WORKING_DIRECTORY"

SERVICE_ZIP_NAME="service.zip"
SERVICE_ZIP_PATH="$GITHUB_WORKSPACE/$SERVICE_ZIP_NAME"
cd "$GITHUB_WORKSPACE"
zip -r "$SERVICE_ZIP_PATH" "$WORKING_DIRECTORY"

ZIPSUM_FILE="zipsum.txt"
SIGNATURE_FILE="ZipSignature"
PACKAGE_FILE="package.zip"
md5sum "$SERVICE_ZIP_PATH" | cut -c -32 > $ZIPSUM_FILE

if [[ -n "$SIGNING_PROFILE" ]]; then
  aws kms sign \
    --key-id "$SIGNING_PROFILE" \
    --message fileb://"$ZIPSUM_FILE" \
    --signing-algorithm RSASSA_PSS_SHA_256 \
    --message-type RAW \
    --output text \
    --query Signature | base64 --decode > $SIGNATURE_FILE
else
  echo "No SIGNING_PROFILE provided, skipping signing step."
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
COMMIT_MESSAGE=$(echo "${HEAD_MESSAGE}" | tr '[]' '()' | tr '\n' ' ' | tr ',' ';' | head -n 1 | cut -c1-50 | xargs)
METADATA="repository=$GITHUB_REPOSITORY,commitsha=$COMMIT_SHA,commitmessage=$COMMIT_MESSAGE,skipapproval=${skip_approval:-false}"
if [ -n "$skip_envs" ]; then
  METADATA="$METADATA,skipapprovalenvs='$skip_envs'"
fi
aws s3 cp $PACKAGE_FILE "s3://${ARTIFACT_BUCKET}/${s3_prefix:-}$PACKAGE_FILE" --metadata "${METADATA}"
aws s3 cp $ZIPSUM_FILE "s3://${ARTIFACT_BUCKET}/${s3_prefix:-}$ZIPSUM_FILE" --metadata "${METADATA}"
