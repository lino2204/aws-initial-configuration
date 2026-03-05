# AWS Bootstrap Configuration

Docker-based bootstrap to create the foundational AWS infrastructure needed for secure GitHub Actions deployments.

## What This Creates

- **S3 Bucket** - Encrypted Terraform state storage with versioning and TLS-only access
- **IAM OIDC Provider** - Allows GitHub Actions to authenticate with AWS without storing credentials
- **IAM Role** - Assumed by your other repositories to deploy resources to AWS

## Prerequisites

- Docker installed
- An IAM user with access and secret key (only needed for the initial bootstrap)
- GitHub repository secrets configured:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`

## Running via GitHub Actions

Trigger the workflow manually from the Actions tab in GitHub. It will create all resources and print the outputs.

## Running Locally

```bash
# With Make
cp .env.example .env   # fill in your credentials
source .env
make bootstrap

# Without Make (Docker only)
docker build -t aws-bootstrap .
docker run --rm \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_REGION=us-east-1 \
  -e GITHUB_ORG=your-github-username \
  aws-bootstrap \
  ./bootstrap.sh
```

## Using the Role in Other Repositories

After bootstrap, add this to any workflow in your GitHub repositories:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - name: Configure AWS Credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::YOUR_ACCOUNT_ID:role/github-actions-terraform
      aws-region: us-east-1
```

And this backend configuration in Terraform:

```hcl
terraform {
  backend "s3" {
    bucket       = "tf-state-YOUR_ACCOUNT_ID-us-east-1"
    key          = "my-project/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

## Security Notes

- Delete the IAM user access keys after the bootstrap completes - they are no longer needed
- Never commit the `.env` file - it contains your AWS credentials
- All future deployments use OIDC, so no AWS credentials need to be stored in GitHub

## Available Make Commands

```bash
make check      # Validate AWS credentials
make plan       # Dry-run, shows what will be created
make bootstrap  # Create all AWS resources
make destroy    # Delete all AWS resources
make test       # Test AWS connectivity
```




