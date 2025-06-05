#!/usr/bin/env bash
shopt -s extglob nocasematch
set -euo pipefail

: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${VERSION:-}"
: "${SIGNING_PROFILE:-}"
: "${ARTIFACT_PREFIX:-}"

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

[[ $COMMIT_MESSAGES =~ \[(skip canary|no canary|canary skip)\] ]] && skip_canary=1
[[ $COMMIT_MESSAGES =~ \[(close circuit breaker|end circuit breaker)\] ]] && close_circuit_breaker=1

release_metadata=(
  "commitsha=$GITHUB_SHA"                                                    # Head commit SHA
  "committag=$(git describe --tags --first-parent --always)"                 # Head commit tag or short SHA
  "commitmessage='$(echo "$HEAD_MESSAGE" | head -n 1 | cut -c1-50)'"         # Shortened head commit subject
  "mergetime=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")" # Merge to main UTC timestamp
  "commitauthor='$GITHUB_ACTOR'"
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
echo "» Zipping CloudFormation template"
zip template.zip "$TEMPLATE_OUT_FILE"

echo "» Uploading artifact to S3"
aws s3 cp template.zip "s3://$ARTIFACT_BUCKET/${s3_prefix:-}template.zip" --metadata "$metadata"
