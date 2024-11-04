#!/usr/bin/env python3
from aws_cdk import Stack
from aws_cdk.assertions import Template

import os, subprocess, sys

stack = Stack()

signing_profile_name = os.environ['SIGNING_PROFILE']
template_file_name = os.environ['TEMPLATE_FILE']
artifact_bucket = os.environ['ARTIFACT_BUCKET']
repository = os.environ['REPOSITORY']
commit_message = os.environ['COMMIT_MESSAGE']
commit_sha = os.environ['GIT_SHA']
commit_tag = os.environ['GIT_TAG']
github_actor = os.environ['GITHUB_ACTOR']
version_number = os.environ['VERSION_NUMBER']
merge_time = os.environ['MERGE_TIME']
skip_canary = os.environ['SKIP_CANARY_DEPLOYMENT']
cf_template = 'cf-template.yaml'

# signing_profile_name = "SigningProfile_2KY7QMWu5CUY"
# template_file_name = "/Users/bgalliano/Projects/GDS/di-devplatform/devplatform-upload-action/sam-app2/.aws-sam/build/json-template.yaml"
# artifact_bucket = "demo-sam-app2-pipeline-githubartifactsourcebucket-kp3njaayiyde"
# repository = "devplatform-demo-sam-app"
# commit_message = "commit message"
# commit_sha = "commit sha"
# commit_tag = "madeuptag"
# github_actor = "Beca Galliano"
# version_number = "v123"
# merge_time = 0
# skip_canary = 0
# cf_template = "/Users/bgalliano/Projects/GDS/di-devplatform/devplatform-upload-action/sam-app2/.aws-sam/build/cf-template.yaml"

def signing_profiles_list(template_file_name):
  with open (template_file_name) as templateFile:
    app_template = Template.from_string(templateFile.read())
    print("Parsing resources to be signed")
    functions = app_template.find_resources(type="AWS::Serverless::Function")
    print("functions", functions)
    layers = app_template.find_resources(type="AWS::Serverless::LayerVersion")
    print("layers", layers)
    resources = functions | layers
    print(resources)
    signing_profiles = []
    print(signing_profiles)

    for resource in resources:
      signing_profiles += f'{resource}={signing_profile_name} '

    print("signing profiles:", ''.join(signing_profiles))

  return ''.join(signing_profiles)

signing_profiles = signing_profiles_list(template_file_name)


def sign_resources(template_file_name, signing_profiles):
  print("Signing resources with sam package")
  if signing_profiles:
    os.system(f'sam package --s3-bucket=a{artifact_bucket} --template-file={template_file_name} --output-template-file=cf-template.yaml --use-json --signing-profiles {signing_profiles}')
  else:
    os.system(f'sam package --s3-bucket={artifact_bucket} --template-file={template_file_name} --output-template-file=cf-template.yaml --use-json')
  return

def lambda_provenance(cf_template):
  print("Writing Lambda provenance")
  with open (cf_template) as cftemplateFile:
    metadata = [f'repository={repository}',
                f'commitsha={commit_sha}',
                f'committag={commit_tag}',
                f'commitmessage={commit_message}',
                f'commitauthor={github_actor}',
                f'release={version_number}']
    metadata = ','.join(metadata)
    app_template = Template.from_string(cftemplateFile.read())
    functions = app_template.find_resources(type="AWS::Serverless::Function")
    layers = app_template.find_resources(type="AWS::Serverless::LayerVersion")

    for resource, configuration in functions.items():
      print("lambda provenance")
      CodeUri = configuration['Properties']['CodeUri']
      print("codeuri:", CodeUri)
      os.system(f'aws s3 cp {CodeUri} {CodeUri} --metadata {metadata}')
      print("metadata:", metadata)

    print ("Writing Lambda Layer provenance")
    for resource, configuration in layers.items():
      print("lambda layer provenance")
      ContentUri = configuration['Properties']['ContentUri']
      os.system(f'aws s3 cp {ContentUri} {ContentUri} --metadata {metadata}')



def upload_artifact():
  print("Zipping the CloudFormation template")
  os.system(f'zip template.zip {cf_template}')
  print("Uploading zipped CloudFormation artifact to S3")
  metadata = [f'repository={repository}',
              f'commitsha={commit_sha}',
              f'committag={commit_tag}',
              f'commitmessage={commit_message}',
              f'commitauthor={github_actor}',
              f'release={version_number}',
              f'mergetime={merge_time}',
              f'skipcanary={skip_canary}',
              f'codepipeline-artifact-revision-summary={version_number}']
  metadata = ','.join(metadata)
  os.system(f'aws s3 cp template.zip "s3://{artifact_bucket}/template.zip" --metadata {metadata}')

signing_profiles_list(template_file_name)
sign_resources(template_file_name, signing_profiles)
lambda_provenance(cf_template)
upload_artifact()
