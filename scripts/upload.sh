#!/usr/bin/env bash
shopt -s nocasematch
set -euo pipefail

: "${COMMIT_MESSAGE:?}"
: "${ARTIFACT_BUCKET:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_ACTOR:?}"

: "${VERSION:-}"
: "${SIGNING_PROFILE:-}"
: "${TEMPLATE_FILE:=template.yaml}"
: "${TEMPLATE_OUT_FILE:=cf-template.yaml}"
: "${GITHUB_SHA:=$(git rev-parse HEAD)}"

echo "» Parsing Lambdas to be signed"

mapfile -t lambdas < <(yq \
  '.Resources[] | select(
    .Type=="AWS::Serverless::Function" or
    .Type=="AWS::Serverless::LayerVersion"
  ) | key' "$TEMPLATE_FILE")

echo "ℹ Found ${#lambdas[@]} Lambda(s) in the template"
echo "::group::Packaging SAM app"

[[ ${SIGNING_PROFILE:-} ]] && signing_profiles=${lambdas[*]/%/=$SIGNING_PROFILE}
[[ ${signing_profiles:-} ]] || echo "⚠ Code will not be signed"

sam package \
  --template-file="$TEMPLATE_FILE" \
  --output-template-file="$TEMPLATE_OUT_FILE" \
  --s3-bucket="$ARTIFACT_BUCKET" \
  --signing-profiles "${signing_profiles:-}"

echo "::endgroup::"
echo "::group::Gathering release metadata"

[[ $COMMIT_MESSAGE =~ \[(skip canary|no canary|canary skip)\] ]] && skip_canary=1

release_metadata=(
  "commitsha=$GITHUB_SHA"                                                                       # Head commit SHA
  "committag=$(git describe --tags --first-parent --always)"                                    # Head commit tag or short SHA
  "commitmessage=$(echo "$COMMIT_MESSAGE" | tr "\n" " " | tr -dc "[:alnum:]#:- " | cut -c1-50)" # Shortened head commit message
  "mergetime=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%F %T")"                    # Merge to main UTC timestamp
  "commitauthor='$GITHUB_ACTOR'"
  "repository=$GITHUB_REPOSITORY"
  "skipcanary=${skip_canary:-0}"
)

[[ ${VERSION:-} ]] && release_metadata+=(
  "codepipeline-artifact-revision-summary=$VERSION"
  "release=$VERSION"
)

metadata=$(IFS="," && echo "${release_metadata[*]}")
column -t -s= < <(tr "," "\n" <<< "$metadata")

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
aws s3 cp template.zip "s3://$ARTIFACT_BUCKET/template.zip" --metadata "$metadata"
