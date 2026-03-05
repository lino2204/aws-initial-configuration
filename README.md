# AWS Bootstrap Configuration

🚀 **Simple Docker-based AWS infrastructure bootstrap for GitHub Actions OIDC**

This project creates the essential AWS resources needed for secure GitHub Actions authentication and Terraform remote state management. Perfect for teams and individuals who want to bootstrap their AWS infrastructure setup quickly and securely.

## What This Creates

✅ **S3 Bucket** - Encrypted Terraform state storage with versioning and TLS-only access  
✅ **IAM OIDC Provider** - GitHub Actions authentication without long-lived credentials  
✅ **IAM Role** - Secure role with least-privilege permissions for deployments  
✅ **Security Policies** - Proper access controls, encryption, and security best practices  

## Why This Approach?

### ✅ **Simple & Fast**
- Pure AWS CLI - no state management complexity
- Single command execution
- Docker-based - works consistently everywhere

### ✅ **Secure by Design**
- No long-lived AWS credentials in GitHub
- OIDC-based authentication
- Least-privilege permissions
- TLS-enforced S3 access

### ✅ **Team-Ready**
- Public repository - easy for teams to use
- Auto-detects GitHub organization
- Consistent across environments
- Easy to debug and modify

## Quick Start

### 1. Prerequisites

- Docker installed
- AWS credentials (temporary - only for bootstrap)
- Make (usually pre-installed)

### 2. Clone and Setup

```bash
# Clone this repository
git clone https://github.com/your-org/aws-initial-configuration.git
cd aws-initial-configuration

# Copy and edit environment file
cp .env.example .env
# Edit .env with your AWS credentials
```

### 3. Configure Environment

Edit `.env` file:
```bash
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=us-east-1
```

### 4. Bootstrap Your Infrastructure

```bash
# Load environment variables
source .env

# Run complete bootstrap
make bootstrap

# Or step by step:
make check      # Validate credentials
make plan       # See what will be created (dry-run)
make bootstrap  # Create infrastructure
```

## Available Commands

```bash
make help       # Show all available commands
make check      # Validate AWS credentials and configuration
make plan       # Show what resources will be created (dry-run)
make bootstrap  # Create all AWS resources
make test       # Test AWS connectivity
make destroy    # Remove all AWS resources (careful!)
make clean      # Clean up Docker resources
```

## Example Output

After successful bootstrap:

```
🎉 Bootstrap completed successfully!

📝 Save these values for your other repositories:

github_actions_role_arn = "arn:aws:iam::123456789012:role/github-actions-terraform"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
state_bucket_name = "tf-state-123456789012-us-east-1"
```

## Using the Bootstrap in Your Projects

### GitHub Actions Workflow

Add this to your repository's `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-terraform
          aws-region: us-east-1
          
      - name: Deploy with Terraform
        run: |
          terraform init
          terraform plan
          terraform apply -auto-approve
```

### Terraform Backend Configuration

Add this to your Terraform configuration:

```hcl
terraform {
  backend "s3" {
    bucket       = "tf-state-123456789012-us-east-1"
    key          = "my-project/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true  # Native S3 locking, requires Terraform 1.10+
    encrypt      = true
  }
}
```

## Advanced Usage

### Custom GitHub Organization

```bash
GITHUB_ORG=my-custom-org make bootstrap
```

### Different AWS Region

```bash
AWS_REGION=eu-west-1 make bootstrap
```

### Dry Run (See What Would Be Created)

```bash
make plan
```

### Testing Credentials

```bash
make test
```

## Troubleshooting

### Docker Issues

```bash
# macOS/Linux: Add user to docker group
sudo usermod -aG docker $USER
# Then logout and login again

# Or use sudo
sudo make bootstrap
```

### AWS Credentials Issues

```bash
# Test your credentials
aws sts get-caller-identity

# Common issues:
# 1. Wrong region in .env file
# 2. Expired or invalid credentials
# 3. Insufficient permissions (need IAM, S3, STS access)
```

### Permission Errors

The bootstrap user needs these minimum permissions:
- `iam:CreateRole`, `iam:CreatePolicy`, `iam:AttachRolePolicy`
- `iam:CreateOpenIDConnectProvider`
- `s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutBucketEncryption`
- `sts:GetCallerIdentity`

## Security Notes

### ⚠️ Important Security Practices

1. **Rotate Bootstrap Credentials** - Delete the IAM user after bootstrap
2. **Never Commit .env** - Contains your AWS credentials
3. **Use Least Privilege** - Create dedicated bootstrap user
4. **Monitor Usage** - Check AWS CloudTrail logs

### ✅ After Bootstrap

1. **Delete IAM Access Keys** - No longer needed
2. **Use OIDC Roles** - For all future deployments
3. **Rotate Regularly** - Follow AWS security best practices

## Project Structure

```
├── bootstrap.sh       # Main bootstrap script (AWS CLI commands)
├── Dockerfile         # Container with AWS CLI and tools
├── Makefile          # User-friendly commands
├── .env.example      # Environment template
├── README.md         # This documentation
└── .github/workflows/ # Simple validation workflow
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## Support

- 🐛 **Issues**: [GitHub Issues](https://github.com/your-org/aws-initial-configuration/issues)
- 📚 **Documentation**: This README
- 💬 **Discussions**: [GitHub Discussions](https://github.com/your-org/aws-initial-configuration/discussions)

## License

MIT License - see LICENSE file for details.

---

**Ready to bootstrap your AWS infrastructure?** 🚀

```bash
make bootstrap
```

*No Terraform state management. No complex workflows. Just simple, secure AWS bootstrap in minutes.*
