# Upload Action

This is an action that allows you to upload a built SAM application to S3 using GitHub Actions.

The action packages, signs the Lambda functions, and uploads the application to the specified S3 bucket.

It adds the following metadata to the S3 object:

| Key             | Description                                                                                                                                                                                                |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `commitsha`     | The full SHA of the head git commit                                                                                                                                                                        |
| `committag`     | The tag of the head git commit, if present, otherwise this falls back to the short commit SHA                                                                                                              |
| `commitmessage` | The first 50 characters of the first line (subject) of the head commit message                                                                                                                             |
| `mergetime`     | The timestamp when the head commit was committed in the UTC timezone. For PRs this is effectively the merge time                                                                                           |
| `commitauthor`  | The name of the person or app that initiated the workflow run                                                                                                                                              |
| `repository`    | The name of the git repository where the workflow was initiated from. This will usually be the repository containing the SAM template being deployed                                                       |
| `skipcanary`    | A flag (0 or 1) to indicate whether the canary deployment should be skipped in the pipeline. This is determined by searching for a special string in the commit messages included in a workflow push event |

## Action Inputs

| Input                | Required | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Example                                  |
|----------------------|----------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------|
| artifact-bucket-name | true     | The name of the artifact S3 bucket                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | artifact-bucket-1234                     |
| signing-profile-name | true     | The name of the Signing Profile in AWS                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | signing-profile-1234                     |
| aws-region           | false    | The name of the region to use when authenticating to AWS                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | eu-west-2                                |
| aws-role-arn         | false    | The ARN of the AWS to assume before uploading the artifact                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | arn:aws:iam::123456789000:role/role-name |
| working-directory    | false    | The directory containing the built SAM application and processed template file                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | ./sam-app                                |
| template-file        | false    | The path of the processed SAM template for the application relative to the working directory; defaults to `template.yaml`                                                                                                                                                                                                                                                                                                                                                                                                                         | .aws-sam/build/template.yaml             |
| version-number       | false    | Deprecated and replaced by `version` but still used as a fallback for backwards compatibility                                                                                                                                                                                                                                                                                                                                                                                                                                                     | version-number-1234                      |
| version              | false    | The version number of the application being deployed. This accepts any input and will used as the value for both the `codepipeline-artifact-revision-summary` and `release` metadata keys. While `codepipeline-artifact-revision-summary` is a special metadata that will display its value in the CodePipeline console, `release` was implemented for a particular team's use case. If left blank, the version keys will not be included in the metadata and CodePipeline will default revision summary to the latest artifact source version ID | version-1234                             |

## Usage Example

Pull in the action in your workflow as below, making sure to specify the release version you require.

```yaml
- name: Deploy SAM app
  uses: govuk-one-login/devplatform-upload-action/sam@<version_number>
  with:
    artifact-bucket-name: ${{ secrets.ARTIFACT_BUCKET_NAME }}
    signing-profile-name: ${{ secrets.SIGNING_PROFILE_NAME }}
    working-directory: ./sam-app
    template-file: .aws-sam/build/template.yaml
```

**Note**: From version 3.12.0 the sam github action has been moved to it's own distinct folder,
This has been done in a backwards compatible manner.

A symbolic link for `sam/action.yaml` remains in the root directory. This allows existing workflows using the SAM Upload Action to continue functioning without adding the `sam` folder path when updating to use a newer version of the github action.

However, this root symlink will be removed in the future. Therefore, we recommend updating your workflow files to point directly to the new `sam` subfolder path when updating to use a newer version of the github action..

## Requirements

- pre-commit:

  ```shell
  brew install pre-commit
  pre-commit install -tpre-commit -tprepare-commit-msg -tcommit-msg
  ```

## Releasing updates

We
follow [recommended best practices](https://docs.github.com/en/actions/creating-actions/releasing-and-maintaining-actions)
for releasing new versions of the action.

### Non-breaking changes

Release a new minor or patch version as appropriate. Then, update the base major version release (and any minor
versions) to point to this latest commit. For example, if the latest major release is v2, and you have added a
non-breaking feature, release v2.1.0 and point v2 to the same commit as v2.1.0.

NOTE: Until v3 is released, you will need to point both v1 and v2 to the latest version since there are no breaking
changes between them.

NOTE: In regard to Dependabot subscribers, Dependabot does not pick up and raise PRs for `PATCH` versions (i.e. v3.8.1)
of a release ensure consumers are notified.

### Breaking changes

Release a new major version as normal following semantic versioning.

### Bug fixes

Once your PR is merged and the bug is fixed, make sure to float tags affected by the bug to the latest stable commit.

For example, let's say commit `abcd001` introduced a bug and is tagged with `v2.3.1`. You then merge commit `dcba002`
with a fix to your solution:

:bug: `abcd001` `v2.3.1`

:white_check_mark: `dcba002`

Instead of creating a new tag for the fix, you can update the `v2.3.1` tag to the latest stable commit with the
following command:

```
git tag -s -af v2.3.1 dcba002
git push origin v2.3.1 -f
```

:bug: `abcd001`

:white_check_mark:`dcba002` `v2.3.1`

This will make sure users benefit from the fix immediately, without the need to manually bump their action version.

### Preparing a release

When working on a PR branch, create a release with the target version, but append -beta to the post-fix tag name.

e.g.

`git tag v3.1-beta`

You can then navigate to the release page, and create a pre-release to validate that the tag is working as expected.
After you've merged the PR, then apply the correct tag for your release.

Please ensure all pre-release versions have been tested prior to creation, you are able to do this via updating `uses:`
property within a GitHub actions workflow to point to a branch name rather than the tag, see example below:

```
jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Upload and tag
        uses: govuk-one-login/devplatform-upload-action/sam@<BRANCH_NAME>
```
