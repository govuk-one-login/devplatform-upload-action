#!/usr/bin/env bash
shopt -s extglob nocasematch
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${VERSION:-}"
: "${SIGNING_PROFILE:-}"
: "${ARTIFACT_PREFIX:-}"
: "${SYNTHETICS_DIRECTORY:-}"

: "${COMMIT_MESSAGES:=}"
: "${HEAD_MESSAGE:=$(git log -1 --format=%s)}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"

: "${TEMPLATE_FILE:=template.yaml}"
: "${TEMPLATE_OUT_FILE:=cf-template.yaml}"

echo "» Parsing Lambdas to be signed"

mapfile -t lambdas < <(yq \
  '.Resources[] | select(
    .Type=="AWS::Serverless::Function" or
    .Type=="AWS::Serverless::LayerVersion"
  ) | key' "$TEMPLATE_FILE")

echo "ℹ Found ${#lambdas[@]} Lambda(s) in the template"
echo "::group::Packaging SAM app"

[[ ${ARTIFACT_PREFIX:-} ]] && s3_prefix=${ARTIFACT_PREFIX%%+(/)}/
[[ ${SIGNING_PROFILE:-} ]] && signing_profiles=${lambdas[*]/%/=$SIGNING_PROFILE}
[[ ${signing_profiles:-} ]] || echo "::notice title=Signing profile not set::Code will not be signed"

sam package \
  --template-file="$TEMPLATE_FILE" \
  --output-template-file="$TEMPLATE_OUT_FILE" \
  --s3-bucket="$ARTIFACT_BUCKET" \
  --s3-prefix "${s3_prefix:+${s3_prefix%/}}" \
  --signing-profiles "${signing_profiles:-}"

echo "::endgroup::"
echo "::group::Gathering release metadata"

if [[ -n "${GITHUB_ACTION_PATH:-}" ]]; then
  echo "WE HAVE ACTION PATH: ${GITHUB_ACTION_PATH}"
  
  # Start search at GITHUB_ACTION_PATH
  FULL_ACTION_PATH="${GITHUB_ACTION_PATH}"
  
  # Walk up parent directories until we find where .github lives
  while [[ "${FULL_ACTION_PATH}" != "/" ]] && [[ ! -d "${FULL_ACTION_PATH}/.github" ]]; do
    FULL_ACTION_PATH="$(cd "${FULL_ACTION_PATH}/.." && pwd)"
  done
  
  SCRIPT_PATH="${FULL_ACTION_PATH}"
else
  echo "NO ACTION PATH (Local / Unit Test)"
  SCRIPT_PATH="$(git rev-parse --show-toplevel)"
fi

METADATA_SCRIPT="${SCRIPT_PATH}/.github/scripts/get-release-metadata.sh"

if [ ! -f "$METADATA_SCRIPT" ]; then
  echo "❌ Could not find script at $METADATA_SCRIPT"
  exit 1
fi

if ! METADATA_VALUES="$("$METADATA_SCRIPT")"; then
  echo "❌ Could not retrieve metadata"
  exit 1
fi

eval "$METADATA_VALUES"

[[ $COMMIT_MESSAGES =~ \[(skip canary|skip canaries|no canary|canary skip)\] ]] && skip_canary=1
[[ $COMMIT_MESSAGES =~ \[(close circuit breaker|end circuit breaker)\] ]] && close_circuit_breaker=1

release_metadata=(
  "commitsha=$GITHUB_SHA"                                                       # Head commit SHA
  "committag=$(git describe --tags --first-parent --always)"                    # Head commit tag or short SHA
  "commitmessage='$(echo "${HEAD_MESSAGE//\'/\\\'}" | head -n 1 | cut -c1-50)'" # Shorten head commit subject and escape '
  "mergetime=$MERGE_TIME"
  "commitauthor='$COMMIT_AUTHOR'"
  "repository=$GITHUB_REPOSITORY"
  "skipcanary=${skip_canary:-0}"
  "closecircuitbreaker=${close_circuit_breaker:-0}"
)

[[ ${VERSION:-} ]] && release_metadata+=(
  "codepipeline-artifact-revision-summary=$VERSION"
  "release=$VERSION"
)

metadata=$(IFS="," && echo "${release_metadata[*]}")
column -ts= < <(tr "," "\n" <<< "$metadata")

echo "::endgroup::"
echo "::group::Writing Lambda provenance"

for lambda in "${lambdas[@]}"; do
  if uri=$(yq --exit-status ".Resources.${lambda}.Properties | .CodeUri // .ContentUri" "$TEMPLATE_OUT_FILE"); then
    echo "❭ $lambda"
    aws s3 cp "$uri" "$uri" --metadata "$metadata"
  fi
done

echo "::endgroup::"

if [[ ${SYNTHETICS_DIRECTORY:-} ]]; then
  echo "::group::Uploading Synthetic Canaries"
  echo "» Parsing Synthetic Canaries to be uploaded"

  mapfile -t synthetic_canaries < <(yq \
    '.Resources[] | select(
      .Type=="AWS::Synthetics::Canary"
    ) | key' "$TEMPLATE_OUT_FILE")

  echo "ℹ Found ${#synthetic_canaries[@]} Synthetic Canary(ies) in the template"

  for synthetic_canary in "${synthetic_canaries[@]}"; do
    if s3_key=$(yq --exit-status ".Resources.${synthetic_canary}.Properties.Code.S3Key" "$TEMPLATE_OUT_FILE"); then
      echo "❭ $synthetic_canary"
      version_id=$(aws s3api put-object \
        --bucket "$ARTIFACT_BUCKET" \
        --key "$s3_key" \
        --body "$SYNTHETICS_DIRECTORY"/"$s3_key" \
        --metadata "$metadata" \
        --query VersionId)

      yq -i ".Resources.${synthetic_canary}.Properties.Code.S3ObjectVersion = $version_id" "$TEMPLATE_OUT_FILE"
    fi
  done

  echo "::endgroup::"
fi

echo "» Zipping CloudFormation template"
zip template.zip "$TEMPLATE_OUT_FILE"

echo "» Uploading artifact to S3"
aws s3 cp template.zip "s3://$ARTIFACT_BUCKET/${s3_prefix:-}template.zip" --metadata "$metadata"
