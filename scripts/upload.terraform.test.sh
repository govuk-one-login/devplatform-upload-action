#!/usr/bin/env bash
set -euo pipefail

source scripts/utility.test.sh

: "${ARTIFACT_BUCKET:?}"
: "${ARTIFACT_PREFIX:=""}"
: "${COMMIT_MESSAGE:=$(git log -1 --format=%s | head -n 1 | cut -c1-200)}"
: "${VERSION:=}"
: "${ZIP_FILE:=package.zip}"

# Overwrite the global `expected_metadata` array in `utility.test.sh` with Terraform-specific keys
expected_metadata=(
  [commitsha]=$GITHUB_SHA
  [commitmessage]=$COMMIT_MESSAGE
  [repository]=$GITHUB_REPOSITORY
)

if [[ -n "$ARTIFACT_PREFIX" ]]; then
  s3_prefix="${ARTIFACT_PREFIX%%+(/)}/"
else
  s3_prefix=""
fi
S3_KEY="${s3_prefix}package.zip"
S3_ZIPSUM="s3://${ARTIFACT_BUCKET}/${s3_prefix}zipsum.txt"

verify-object-metadata "$S3_KEY" "Terraform Artifact"
echo "✅ Verified metadata successfully"
verify-terraform-zip-contents "$S3_KEY"
echo "✅ Verified zip contents successfully"
verify-terraform-zipsum "$S3_ZIPSUM"
echo "✅ Verified zipsum successfully"
