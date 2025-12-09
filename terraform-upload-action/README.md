# Terraform Upload Action

This is an action that allows you to package, sign and uploads Terraform configurations to S3 for secure infra pipelines using GitHub Actions.

It adds the following metadata to the S3 object:

| Key             | Description                                                                                                                                                                                                |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `commitsha`     | The full SHA of the head git commit |
| `commitmessage` | The first 50 characters of the first line (subject) of the head commit message |
| `repository`    | The name of the git repository where the workflow was initiated from. This will usually be the repository containing the terraform configuration deployed |

## Action Inputs

| Input | Required |Description | Example |
|----------|----------|----------|----------|
| artifact-bucket-name | true     | The name of the artifact S3 bucket | artifact-bucket-1234 |
| signing-profile-name | false     | The name of the Signing Profile in AWS | signing-profile-1234 |
| aws-region           | false    | The name of the region to use when authenticating to AWS | eu-west-2 |
| aws-role-arn         | false    | The ARN of the AWS to assume before uploading the artifact |arn:aws:iam::123456789000:role/role-name |
| working-directory    | false    | The directory containing terraform | ./terraform |
## Usage Example

Pull in the action in your workflow as below, making sure to specify the release version you require.

```yaml
- name: Publish Terraform Artifact
  uses: govuk-one-login/devplatform-upload-action/terraform-upload-action@<version-number>
  with:
    working-directory: './terraform'
    aws-role-arn: ${{ vars.SECURE_INFRA_PIPELINE_ROLE }}
    artifact-bucket-name: ${{ vars.SECURE_INFRA_SOURCE_BUCKET }}
    signing-profile-name: ${{ vars.SECURE_INFRA_ZIP_SIGNING_KEY }}
    aws-region: 'eu-west-2'
```

## Requirements

- pre-commit:

  ```shell
  brew install pre-commit
  pre-commit install -tpre-commit -tprepare-commit-msg -tcommit-msg
  ```

## Releasing updates

We follow [recommended best practices](https://docs.github.com/en/actions/creating-actions/releasing-and-maintaining-actions) for releasing new versions of the action.

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
        uses: govuk-one-login/devplatform-upload-action/terraform-upload-action@<BRANCH_NAME>
```
