#! /bin/bash
shopt -s nocasematch
set -eu

: "${ARTIFACT_BUCKET}"
: "${SIGNING_PROFILE}"
: "${COMMIT_MESSAGE}"
: "${GITHUB_ACTOR}"
: "${VERSION_NUMBER:=}"
: "${TEMPLATE_FILE:=template.yaml}"

echo "Parsing lambdas to be signed"

mapfile -t lambdas < <(yq \
  '.Resources[] | select(
    .Type=="AWS::Serverless::Function" or
    .Type=="AWS::Serverless::LayerVersion"
  ) | key' "$TEMPLATE_FILE")

echo "Packaging SAM app"
[[ ${#lambdas[@]} -eq 0 ]] && echo "ℹ No lambdas require signing"

sam package \
  --template-file="$TEMPLATE_FILE" \
  --output-template-file=cf-template.yaml \
  --s3-bucket="$ARTIFACT_BUCKET" \
  --signing-profiles "${lambdas[*]/%/=$SIGNING_PROFILE}"

# Get the current commit tag or short SHA if there isn't one
git_tag=$(git describe --tags --first-parent --always)

# Remove special characters from the commit message
commit_msg=$(echo "$COMMIT_MESSAGE" | tr "\n" " " | tr -dc "[:alnum:]#:- " | cut -c1-50)

# Get merge to main UTC timestamp
merge_timestamp=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:"%Y-%m-%d %H:%M:%S")

# Search for instructions to skip canary deployment in the commit message
[[ $COMMIT_MESSAGE =~ \[(skip canary|no canary|canary skip)\] ]] &&
  skip_canary_deployment=1 ||
  skip_canary_deployment=0

echo "Writing Lambda provenance"
yq '.Resources.* | select(has("Type") and has("Properties.CodeUri") and .Type == "AWS::Serverless::Function") | .Properties.CodeUri' cf-template.yaml |
  xargs -L1 -I{} aws s3 cp "{}" "{}" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$git_tag,commitmessage=$commit_msg,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER"

echo "Writing Lambda Layer provenance"
yq '.Resources.* | select(has("Type") and .Type == "AWS::Serverless::LayerVersion") | .Properties.ContentUri' cf-template.yaml |
  xargs -L1 -I{} aws s3 cp "{}" "{}" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$git_tag,commitmessage=$commit_msg,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER"

echo "Zipping the CloudFormation template"
zip template.zip cf-template.yaml

echo "Uploading zipped CloudFormation artifact to S3"
aws s3 cp template.zip "s3://$ARTIFACT_BUCKET/template.zip" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$git_tag,commitmessage=$commit_msg,mergetime=$merge_timestamp,skipcanary=$skip_canary_deployment,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER,codepipeline-artifact-revision-summary=$VERSION_NUMBER"
