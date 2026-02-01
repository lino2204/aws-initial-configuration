data "aws_caller_identity" "current" {}

locals {
  tags = {
    ManagedBy = "Terraform"
    Repo      = "aws-terraform-bootstrap"
  }

  effective_sub_claims = length(var.allowed_sub_claims) > 0 ? var.allowed_sub_claims : [
    "repo:${var.github_org}/*:*"
  ]
}

# ----------------------------
# Terraform remote state (S3)
# ----------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enforce TLS-only access to the state bucket
data "aws_iam_policy_document" "tf_state_bucket_policy" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.tf_state_bucket_policy.json
}

# ----------------------------
# GitHub OIDC Provider
# ----------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Common GitHub Actions root CA thumbprint used in many setups.
  # If your AWS provider version doesn't require it, it still works.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.tags
}

# ----------------------------
# IAM Role for GitHub Actions (assume via OIDC)
# ----------------------------
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.effective_sub_claims
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.github_role_name
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  tags = local.tags
}

# Create a more restrictive policy instead of AdministratorAccess
data "aws_iam_policy_document" "github_actions_permissions" {
  # Terraform state access (S3 native locking - no DynamoDB needed)
  statement {
    sid = "TerraformStateAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]
  }

  # Add common deployment permissions
  # Adjust these based on what your other repos actually need
  statement {
    sid = "CommonDeploymentPermissions"
    actions = [
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
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions" {
  name        = "${var.github_role_name}-policy"
  description = "Permissions for GitHub Actions deployments"
  policy      = data.aws_iam_policy_document.github_actions_permissions.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

# Optional: Uncomment if you really need full admin access (NOT RECOMMENDED)
# resource "aws_iam_role_policy_attachment" "admin" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }
