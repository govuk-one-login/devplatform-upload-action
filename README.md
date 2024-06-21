# Upload Action

This is an action that allows you to upload a built SAM application to S3 using GitHub Actions.

The action packages, signs the Lambda functions, and uploads the application to the specified S3 bucket.

It adds the following metadata to the S3 object:

- committag - The tag of the git commit (if present), this falls back to a shortened commit has.
- repository - The git repository where the file was loaded from.
- commitmessage - The first 50 characters of the git commit message, trimmed to the following regex: `tr -dc '[:alnum:]- '`
- commitsha - The full git commitsha of the git commit.
- mergetime - Time in UTC when git merge happend.
- skipcanary - 0 or 1 for skipcanary.

## Action Inputs

| Input                | Required | Description                                                                              | Example                             |
|----------------------|----------|------------------------------------------------------------------------------------------|-------------------------------------|
| artifact-bucket-name | true     | The name of the artifact S3 bucket                                                       | artifact-bucket-1234                |
| signing-profile-name | true     | The name of the Signing Profile resource in AWS                                          | signing-profile-1234                |
| working-directory    | false    | The working directory containing the SAM app and the template file                       | ./sam-app                           |
| template-file        | false    | The name and path of the CF template for the application. This defaults to template.yaml | .aws-sam/build/template.yaml        |

## Usage Example

Pull in the action in your workflow as below, making sure to specify the release version you require.

```yaml
- name: Deploy SAM app
  uses: govuk-one-login/devplatform-upload-action@<version_number>
  with:
    artifact-bucket-name: ${{ secrets.ARTIFACT_BUCKET_NAME }}
    signing-profile-name: ${{ secrets.SIGNING_PROFILE_NAME }}
    working-directory: ./sam-app
    template-file: .aws-sam/build/template.yaml
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

Release a new minor or patch version as appropriate. Then, update the base major version release (and any minor versions)
to point to this latest commit. For example, if the latest major release is v2 and you have added a non-breaking feature,
release v2.1.0 and point v2 to the same commit as v2.1.0.

NOTE: Until v3 is released, you will need to point both v1 and v2 to the latest version since there are no breaking changes between them.

NOTE: In regards to Dependabot subcribers, Dependabot does not pick up and raise PRs for `PATCH` versions (i.e v3.8.1) of a release ensure consumers are nofitied.

### Breaking changes

Release a new major version as normal following semantic versioning.

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
        uses: govuk-one-login/devplatform-upload-action@<BRANCH_NAME>
```