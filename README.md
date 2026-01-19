# Upload Actions

This repository contains specialized GitHub Actions for packaging, signing, and uploading infrastructure artifacts to S3.

---

## 📂 Available Actions

### [SAM Upload Action](./sam)
This action allows you to upload a built SAM application to S3 using GitHub Actions. It packages and signs the Lambda functions, then uploads to the specified S3 bucket.

### [Terraform Upload Action](./terraform)
This action allows you to package, sign, and upload Terraform configurations to S3 for secure infrastructure pipelines using GitHub Actions.

---

## 📖 Usage Instructions

Usage examples and input parameters are provided in the README for each action within its respective folder:

* For **SAM Upload** instructions, see [sam/README.md](./sam/README.md).
* For **Terraform Upload** instructions, see [terraform/README.md](./terraform/README.md).

---

## 🛠 Repository Structure

* `/sam`: Contains the `action.yaml` for SAM applications.
* `/terraform`: Contains the `action.yaml` for Terraform configurations.

## Note for Existing Users
A symbolic link for `sam/action.yaml` remains in the root directory. This allows existing workflows using the SAM Upload Action to continue functioning without modification.

This root symlink will be removed in the future. Therefore, we recommend updating your workflow files to point directly to the new `sam` subfolder path.
