#!/bin/bash
set -euo pipefail
shopt -s extglob nocasematch

: "${WORKING_DIRECTORY:?}"
: "${ARTIFACT_BUCKET:?}"
: "${SIGNING_PROFILE:-}"
: "${HEAD_MESSAGE:=$(git log -1 --format=%s)}"
: "${COMMIT_SHA:=$(git rev-parse HEAD)}"
: "${GITHUB_REPOSITORY:?}"

cd "$GITHUB_WORKSPACE"
if [ ! -d "$WORKING_DIRECTORY" ]; then
  echo "Error: Working directory $WORKING_DIRECTORY not found." >&2
  exit 1
fi
cd "$WORKING_DIRECTORY"
terraform get

SERVICE_ZIP_NAME="service.zip"
SERVICE_ZIP_PATH="$GITHUB_WORKSPACE/$SERVICE_ZIP_NAME"
cd "$GITHUB_WORKSPACE"
zip -r "$SERVICE_ZIP_PATH" "$WORKING_DIRECTORY"

ZIPSUM_FILE="zipsum.txt"
SIGNATURE_FILE="ZipSignature"
PACKAGE_FILE="package.zip"
md5sum "$SERVICE_ZIP_PATH" | cut -c -32 > $ZIPSUM_FILE

aws kms sign \
  --key-id "$SIGNING_PROFILE" \
  --message fileb://"$ZIPSUM_FILE" \
  --signing-algorithm RSASSA_PSS_SHA_256 \
  --message-type RAW \
  --output text \
  --query Signature | base64 --decode > $SIGNATURE_FILE

zip -r $PACKAGE_FILE "$SERVICE_ZIP_NAME" "$SIGNATURE_FILE"

COMMIT_MESSAGE=$(echo "$HEAD_MESSAGE" | tr '\n' ' ' | tr -d '"[]' | cut -c1-200)
METADATA="repository=$GITHUB_REPOSITORY,commitsha=$COMMIT_SHA,commitmessage=$COMMIT_MESSAGE"

aws s3 cp $PACKAGE_FILE "s3://${ARTIFACT_BUCKET}/$PACKAGE_FILE" --metadata "${METADATA}"
aws s3 cp $ZIPSUM_FILE "s3://${ARTIFACT_BUCKET}/$ZIPSUM_FILE" --metadata "${METADATA}"
