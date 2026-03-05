#!/bin/bash

# AWS Bootstrap Script
# Creates essential AWS infrastructure for Terraform state and GitHub Actions OIDC
# Author: AWS Bootstrap Project
# Usage: ./bootstrap.sh [--dry-run] [--destroy]

set -euo pipefail

# Colors for output
BLUE='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Default values
DRY_RUN=false
DESTROY_MODE=false
AWS_REGION=${AWS_REGION:-us-east-1}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --destroy)
            DESTROY_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--destroy] [--help]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --destroy    Destroy bootstrap infrastructure"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

run_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would run: $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd"; then
        log_success "✅ $description completed"
        return 0
    else
        log_error "❌ Failed: $description"
        return 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        log_error "AWS credentials not found. Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        exit 1
    fi
    
    # Test AWS connectivity
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Cannot connect to AWS. Please check your credentials and region"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

get_account_info() {
    log_info "Getting AWS account information..."
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CALLER_INFO=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    # Try to auto-detect GitHub org from git remote
    if command -v git &> /dev/null && git remote get-url origin &> /dev/null; then
        GITHUB_ORG=${GITHUB_ORG:-$(git remote get-url origin | sed -n 's#.*[:/]\([^/]*\)/[^/]*\.git.*#\1#p')}
    fi
    
    # Set default if still not found
    GITHUB_ORG=${GITHUB_ORG:-"your-github-org"}
    
    # Generate resource names
    STATE_BUCKET="tf-state-${ACCOUNT_ID}-${AWS_REGION}"
    ROLE_NAME="${GITHUB_ROLE_NAME:-github-actions-terraform}"
    POLICY_NAME="${ROLE_NAME}-policy"
    OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
    
    echo ""
    echo -e "${BLUE}📋 Configuration Summary:${RESET}"
    echo "  AWS Account ID: $ACCOUNT_ID"
    echo "  AWS Region: $AWS_REGION"
    echo "  Caller Identity: $CALLER_INFO"
    echo "  GitHub Org: $GITHUB_ORG"
    echo "  S3 Bucket: $STATE_BUCKET"
    echo "  IAM Role: $ROLE_NAME"
    echo "  IAM Policy: $POLICY_NAME"
    echo ""
}

create_s3_bucket() {
    log_info "Creating S3 bucket for Terraform state..."
    
    # Create bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        run_command "aws s3api create-bucket --bucket '$STATE_BUCKET' --region '$AWS_REGION'" \
                   "Creating S3 bucket: $STATE_BUCKET"
    else
        run_command "aws s3api create-bucket --bucket '$STATE_BUCKET' --region '$AWS_REGION' --create-bucket-configuration LocationConstraint='$AWS_REGION'" \
                   "Creating S3 bucket: $STATE_BUCKET"
    fi
    
    # Enable versioning
    run_command "aws s3api put-bucket-versioning --bucket '$STATE_BUCKET' --versioning-configuration Status=Enabled" \
               "Enabling versioning on S3 bucket"
    
    # Enable encryption
    run_command "aws s3api put-bucket-encryption --bucket '$STATE_BUCKET' --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'" \
               "Enabling encryption on S3 bucket"
    
    # Block public access
    run_command "aws s3api put-public-access-block --bucket '$STATE_BUCKET' --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
               "Blocking public access to S3 bucket"
    
    # Add bucket policy for TLS-only access
    local bucket_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyInsecureConnections",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    "arn:aws:s3:::'$STATE_BUCKET'",
                    "arn:aws:s3:::'$STATE_BUCKET'/*"
                ],
                "Condition": {
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            }
        ]
    }'
    
    run_command "aws s3api put-bucket-policy --bucket '$STATE_BUCKET' --policy '$bucket_policy'" \
               "Adding TLS-only policy to S3 bucket"
}

create_oidc_provider() {
    log_info "Creating GitHub OIDC provider..."
    
    # GitHub Actions OIDC provider thumbprint (as of 2024)
    THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
    
    run_command "aws iam create-open-id-connect-provider --url '$OIDC_PROVIDER_URL' --client-id-list sts.amazonaws.com --thumbprint-list '$THUMBPRINT' --tags 'Key=ManagedBy,Value=AWSBootstrap' 'Key=Purpose,Value=GitHubActions'" \
               "Creating GitHub OIDC provider"
}

create_iam_role() {
    log_info "Creating IAM role for GitHub Actions..."
    
    # Trust policy for GitHub Actions
    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Federated": "arn:aws:iam::'$ACCOUNT_ID':oidc-provider/token.actions.githubusercontent.com"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                    },
                    "StringLike": {
                        "token.actions.githubusercontent.com:sub": "repo:'$GITHUB_ORG'/*:*"
                    }
                }
            }
        ]
    }'
    
    run_command "aws iam create-role --role-name '$ROLE_NAME' --assume-role-policy-document '$trust_policy' --tags 'Key=ManagedBy,Value=AWSBootstrap' 'Key=Purpose,Value=GitHubActions'" \
               "Creating IAM role: $ROLE_NAME"
    
    # Create permissions policy
    local permissions_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "TerraformStateAccess",
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'$STATE_BUCKET'",
                    "arn:aws:s3:::'$STATE_BUCKET'/*"
                ]
            },
            {
                "Sid": "CommonDeploymentPermissions",
                "Effect": "Allow",
                "Action": [
                    "ec2:*",
                    "elasticloadbalancing:*",
                    "autoscaling:*",
                    "cloudwatch:*",
                    "logs:*",
                    "iam:GetRole",
                    "iam:PassRole",
                    "iam:GetPolicy",
                    "iam:GetPolicyVersion",
                    "iam:ListPolicies",
                    "iam:ListRoles",
                    "lambda:*",
                    "apigateway:*",
                    "s3:*",
                    "cloudformation:*",
                    "ecs:*",
                    "ecr:*",
                    "rds:*",
                    "secretsmanager:*",
                    "ssm:*"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    run_command "aws iam create-policy --policy-name '$POLICY_NAME' --policy-document '$permissions_policy' --tags 'Key=ManagedBy,Value=AWSBootstrap' 'Key=Purpose,Value=GitHubActions'" \
               "Creating IAM policy: $POLICY_NAME"
    
    # Attach policy to role
    run_command "aws iam attach-role-policy --role-name '$ROLE_NAME' --policy-arn 'arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME'" \
               "Attaching policy to role"
}

destroy_resources() {
    log_warning "🗑️  Destroying bootstrap infrastructure..."
    
    if [ "$DRY_RUN" = false ]; then
        echo -e "${RED}This will permanently delete all bootstrap resources!${RESET}"
        read -p "Type 'destroy' to confirm: " confirm
        if [ "$confirm" != "destroy" ]; then
            log_info "Destruction cancelled"
            exit 0
        fi
    fi
    
    # Detach and delete IAM policy
    run_command "aws iam detach-role-policy --role-name '$ROLE_NAME' --policy-arn 'arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME' 2>/dev/null || true" \
               "Detaching IAM policy from role"
    
    run_command "aws iam delete-policy --policy-arn 'arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME' 2>/dev/null || true" \
               "Deleting IAM policy: $POLICY_NAME"
    
    # Delete IAM role
    run_command "aws iam delete-role --role-name '$ROLE_NAME' 2>/dev/null || true" \
               "Deleting IAM role: $ROLE_NAME"
    
    # Delete OIDC provider
    run_command "aws iam delete-open-id-connect-provider --open-id-connect-provider-arn 'arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com' 2>/dev/null || true" \
               "Deleting GitHub OIDC provider"
    
    # Empty and delete S3 bucket
    run_command "aws s3 rm s3://'$STATE_BUCKET' --recursive 2>/dev/null || true" \
               "Emptying S3 bucket"
    
    run_command "aws s3api delete-bucket --bucket '$STATE_BUCKET' 2>/dev/null || true" \
               "Deleting S3 bucket: $STATE_BUCKET"
    
    log_success "🗑️  Destruction completed"
}

show_outputs() {
    if [ "$DRY_RUN" = true ] || [ "$DESTROY_MODE" = true ]; then
        return
    fi
    
    echo ""
    echo -e "${GREEN}🎉 Bootstrap completed successfully!${RESET}"
    echo ""
    echo -e "${YELLOW}📝 Save these values for your other repositories:${RESET}"
    echo ""
    echo "github_actions_role_arn = \"arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}\""
    echo "github_oidc_provider_arn = \"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com\""
    echo "state_bucket_name = \"${STATE_BUCKET}\""
    echo ""
    echo -e "${BLUE}📚 How to use in other repositories:${RESET}"
    echo ""
    echo "1. Add this to your GitHub Actions workflow:"
    echo ""
    echo "   - name: Configure AWS credentials"
    echo "     uses: aws-actions/configure-aws-credentials@v4"
    echo "     with:"
    echo "       role-to-assume: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    echo "       aws-region: ${AWS_REGION}"
    echo ""
    echo "2. Use this backend in your Terraform configuration:"
    echo ""
    echo "   terraform {"
    echo "     backend \"s3\" {"
    echo "       bucket       = \"${STATE_BUCKET}\""
    echo "       key          = \"your-project/terraform.tfstate\""
    echo "       region       = \"${AWS_REGION}\""
    echo "       use_lockfile = true"
    echo "       encrypt      = true"
    echo "     }"
    echo "   }"
    echo ""
}

main() {
    echo -e "${BLUE}"
    echo "🚀 AWS Bootstrap Configuration"
    echo "============================="
    echo -e "${RESET}"
    
    check_prerequisites
    get_account_info
    
    if [ "$DESTROY_MODE" = true ]; then
        destroy_resources
    else
        create_s3_bucket
        create_oidc_provider
        create_iam_role
        show_outputs
    fi
}

# Run main function
main "$@"