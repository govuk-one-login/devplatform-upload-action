#! /bin/bash

set -eu

echo "Parsing resources to be signed"
RESOURCES="$(yq '.Resources.* | select(has("Type") and .Type == "AWS::Serverless::Function" or .Type == "AWS::Serverless::LayerVersion") | path | .[1]' "$TEMPLATE_FILE" | xargs)"
read -ra LIST <<< "$RESOURCES"

# Construct the signing-profiles argument list
# e.g.: (HelloWorldFunction1="signing-profile-name" HelloWorldFunction2="signing-profile-name")
PROFILES=("${LIST[@]/%/="$SIGNING_PROFILE"}")

echo "Packaging SAM app"
if [ "${#PROFILES[@]}" -eq 0 ]
then
  echo "No resources that require signing found"
  sam package --s3-bucket="$ARTIFACT_BUCKET" --template-file="$TEMPLATE_FILE" --output-template-file=cf-template.yaml
else
  sam package --s3-bucket="$ARTIFACT_BUCKET" --template-file="$TEMPLATE_FILE" --output-template-file=cf-template.yaml --signing-profiles "${PROFILES[*]}"
fi

# This only gets set if there is a tag on the current commit.
GIT_TAG=$(git describe --tags --first-parent --always)
# Cleaning the commit message to remove special characters
COMMIT_MSG=$(echo $COMMIT_MESSAGE | tr '\n' ' ' | tr -dc '[:alnum:]- ' | cut -c1-50)
# Gets merge time to main - displaying it in UTC timezone
MERGE_TIME=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:'%Y-%m-%d %H:%M:%S')

# Sanitise commit message and search for canary deployment instructions
MSG=$(echo $COMMIT_MESSAGE | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')
if [[ $MSG =~ "[skip canary]" || $MSG =~ "[canary skip]" || $MSG =~ "[no canary]" ]]; then
    SKIP_CANARY_DEPLOYMENT=1
else
    SKIP_CANARY_DEPLOYMENT=0
fi

echo "Writing Lambda provenance"
yq '.Resources.* | select(has("Type") and has("Properties.CodeUri") and .Type == "AWS::Serverless::Function") | .Properties.CodeUri' cf-template.yaml \
    | xargs -L1 -I{} aws s3 cp "{}" "{}" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$GIT_TAG,commitmessage=$COMMIT_MSG,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER"
echo "Writing Lambda Layer provenance"
yq '.Resources.* | select(has("Type") and .Type == "AWS::Serverless::LayerVersion") | .Properties.ContentUri' cf-template.yaml \
    | xargs -L1 -I{} aws s3 cp "{}" "{}" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$GIT_TAG,commitmessage=$COMMIT_MSG,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER"

echo "Zipping the CloudFormation template"
zip template.zip cf-template.yaml

echo "Uploading zipped CloudFormation artifact to S3"
aws s3 cp template.zip "s3://$ARTIFACT_BUCKET/template.zip" --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA,committag=$GIT_TAG,commitmessage=$COMMIT_MSG,mergetime=$MERGE_TIME,skipcanary=$SKIP_CANARY_DEPLOYMENT,commitauthor='$GITHUB_ACTOR',release=$VERSION_NUMBER,codepipeline-artifact-revision-summary=$VERSION_NUMBER"
