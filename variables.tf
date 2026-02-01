variable "aws_region" {
  type        = string
  description = "AWS region where bootstrap resources will live"
}

variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform remote state"
}

variable "github_org" {
  type        = string
  description = "GitHub owner/org whose repos are allowed to assume the role"
}

variable "github_role_name" {
  type        = string
  description = "IAM role name assumed by GitHub Actions via OIDC"
  default     = "github-actions-terraform"
}

# Optional: override if you want to restrict to specific repos/branches/environments.
# If empty, defaults to "repo:<github_org>/*:*" (all repos, branches, and environments)
# Examples:
#   - "repo:myorg/myrepo:*" (only myrepo, any branch/env)
#   - "repo:myorg/*:ref:refs/heads/main" (all repos, only main branch)
#   - "repo:myorg/*:environment:production" (all repos, only production environment)
variable "allowed_sub_claims" {
  type        = list(string)
  description = "Allowed GitHub OIDC sub claims"
  default     = []
}
