# Terraform backend configuration for AWS

Configure automatically Terraform backend resources

## Prerequisites

1. **IAM User Setup**: Create an IAM user manually in your AWS account with appropriate permissions (this is only needed for the initial bootstrap)
2. **GitHub Repository Secrets**: Store the following secrets in your GitHub repository settings:
   - `AWS_ACCESS_KEY_ID`: The access key for your IAM user
   - `AWS_SECRET_ACCESS_KEY`: The secret key for your IAM user
   - `AWS_REGION`: The AWS region where you want to deploy (e.g., `us-east-1`)
