#!/usr/bin/env python3
from aws_cdk import Stack
from aws_cdk.assertions import Template

import os, subprocess

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

print(template_file_name)

with open (template_file_name) as templateFile:
  app_template = Template.from_string(templateFile.read())
  print("Parsing resources to be signed")
  functions = app_template.find_resources(type="AWS::Serverless::Function")
  layers = app_template.find_resources(type="AWS::Serverless::LayerVersion")
  signing_profiles = ""

  for resource in layers + functions:
    signing_profiles += f'{resource}={signing_profile_name} '
  if len(functions) + len(layers) == 0:
    print("No resources that require signing found")
    subprocess.run(['sam package',
                  '--s3-bucket="$ARTIFACT_BUCKET"',
                  f'--template-file={template_file_name}',
                  '--output-template-file=cf-template.yaml',
                  ])

  else:
    subprocess.run(['sam package',
              '--s3-bucket="$ARTIFACT_BUCKET"',
              f'--template-file={template_file_name}',
              '--output-template-file=cf-template.yaml',
              f'--signing-profiles {signing_profiles}',
              ])


print("Writing Lambda provenance")

with open (f'cf-template.yaml') as cftemplateFile:
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
  for resource,configuration in functions.items():
    CodeUri = configuration['Properties']['CodeUri']
    subprocess.run([f'aws s3 cp {CodeUri} {CodeUri}',f'--metadata {metadata}'])

  print ("Writing Lambda Layer provenance")
  for resource,configuration in layers.items():
    ContentUri = configuration['Properties']['ContentUri']
    subprocess.run([f'aws s3 cp {ContentUri} {ContentUri}',f'--metadata {metadata}'])

print("Zipping the CloudFormation template")
subprocess.run('zip template.zip cf-template.yaml')

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
subprocess.run(f'aws s3 cp template.zip "s3://{artifact_bucket}/template.zip"',
               f'--metadata {metadata}')
