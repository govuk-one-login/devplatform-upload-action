# Terraform Upload Action

This is an action that allows you to package, sign and upload Terraform configurations to S3 for secure infra pipelines using GitHub Actions.

It adds the following metadata to the S3 object:

| Key             | Description                                                                                                                                                                                                |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `commitsha`     | The full SHA of the head git commit |
| `commitmessage` | The first 50 characters of the first line (subject) of the head commit message |
| `repository`    | The name of the git repository where the workflow was initiated from. This will usually be the repository containing the terraform configuration deployed |
| `skipapproval`  | Flag to indicate if the requirement for manual approval should be overridden via the [auto-approve-all] or [skip-appproval] magic flags |
| `skipapprovalenvs` | Comma delimited list of environments where the requirement for manual approval should be overridden via the [auto-approve-_ENV_] or [skip-appproval-_ENV_] magic flags (where _ENV_ is a the name of an environment eg `dev`, `production`) |

## Usage Example

Pull in the action in your workflow as below, making sure to specify the release version you require.

```yaml
- name: Publish Terraform Artifact
  uses: govuk-one-login/devplatform-upload-action/terraform@<version>
  with:
    working-directory: './terraform'
    aws-role-arn: ${{ vars.SECURE_INFRA_PIPELINE_ROLE }}
    artifact-bucket-name: ${{ vars.SECURE_INFRA_SOURCE_BUCKET }}
    kms-key-arn: ${{ vars.SECURE_INFRA_ZIP_SIGNING_KEY }}
    aws-region: 'eu-west-2'
```

## Features

### Download and package Terraform modules

If your Terraform configuration uses modules stored in a separate private repository, you will need to pull and package them with your code. This is because the infra pipeline currently does not support authenticating to GitHub. The recommended way to do this is to have your workflow authenticate using a GitHub App with read access to your repositories.

The example below shows a workflow that generates a token from a GitHub App with read access to `ipv-terraform-modules` repository. The Github token is passed to the action using `github-token` input. In addition, if your Terraform code lives in a different path to `working-directory`, provide a `terraform-root` path.

```yaml
steps:
  - uses: actions/create-github-app-token@v3
    id: app-token
    with:
      app-id: ${{ secrets.INFRAPIPELINE_CLIENTID }}
      private-key: ${{ secrets.INFRAPIPELINE_PEMKEY }}
      repositories: |
        ipv-terraform-modules

  - name: Publish Terraform Artifact
    uses: govuk-one-login/devplatform-upload-action/terraform@<version>
    with:
      working-directory: './terraform'
      terraform-root: './terraform/stacks/base-stacks'
      aws-role-arn: ${{ vars.SECURE_INFRA_PIPELINE_ROLE }}
      artifact-bucket-name: ${{ vars.SECURE_INFRA_SOURCE_BUCKET }}
      kms-key-arn: ${{ vars.SECURE_INFRA_ZIP_SIGNING_KEY }}
      github-token: ${{ steps.app-token.outputs.token }}
      aws-region: 'eu-west-2'
```

Alternatively, you can setup your own workflow steps to fetch module dependencies before running devplatform-upload-action/terraform.

For more information on GitHub apps usage, visit the [gds-way documentation page](https://gds-way.digital.cabinet-office.gov.uk/standards/source-code/using-github-actions.html#authorizing-github-actions)

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
        uses: govuk-one-login/devplatform-upload-action/terraform@<BRANCH_NAME>
```
