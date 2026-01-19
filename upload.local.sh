#!/usr/bin/env bash
set -euo pipefail

: "${SIGN_CODE:=false}"
: "${NO_PREFIX:=false}"
: "${GITHUB_ACTOR:=$(whoami)}"
: "${GITHUB_REPOSITORY:=upload-action-local}"

default_bucket=upload-action-test-local
[[ $(aws sts get-caller-identity --query Arn --output text) =~ \/([^\/\.]+)\. ]] && user="${BASH_REMATCH[1]}" || exit

if ! [[ ${TEMPLATE_FILE:-} ]]; then
  demo_app="$(dirname "${BASH_SOURCE[0]}")/../devplatform-demo-sam-app/sam-app2"
  export TEMPLATE_FILE="$demo_app/.aws-sam/build/template.yaml"

  if ! [[ -f $TEMPLATE_FILE ]]; then
    echo "» Building demo sam app"
    pushd "$demo_app" > /dev/null
    sam build --cached --parallel
    popd > /dev/null
  fi
fi

if ! [[ ${ARTIFACT_BUCKET:-} ]]; then
  export ARTIFACT_BUCKET=$default_bucket

  if ! aws s3 ls $ARTIFACT_BUCKET &> /dev/null; then
    aws s3 mb "s3://$ARTIFACT_BUCKET"
    aws s3api put-bucket-versioning --bucket $ARTIFACT_BUCKET --versioning-configuration Status=Enabled
  fi
fi

if $SIGN_CODE; then
  SIGNING_PROFILE=$(aws signer list-signing-profiles --query 'profiles[0].profileName' --output text)
  echo "ℹ Using signing profile $SIGNING_PROFILE"
  export SIGNING_PROFILE
fi

export GITHUB_ACTOR GITHUB_REPOSITORY
$NO_PREFIX || export ARTIFACT_PREFIX=${ARTIFACT_PREFIX:-$user}

echo "ℹ Using template $TEMPLATE_FILE"
echo "ℹ Using bucket $ARTIFACT_BUCKET/${ARTIFACT_PREFIX:-}"

scripts/upload.sam.sh
