# This creates an IAM role that GitHub Actions can assume
# Run this once

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
}

# Use data source for existing role to avoid EntityAlreadyExists
data "aws_iam_role" "github_actions" {
  name = "github-actions-twin-deploy"
}

# Comment out the resource since it already exists and we are using the data source
/*
resource "aws_iam_role" "github_actions" {
  name = "github-actions-twin-deploy"
  ...
}
*/

resource "aws_iam_role_policy_attachment" "admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = data.aws_iam_role.github_actions.name
}

output "github_actions_role_arn" {
  value = data.aws_iam_role.github_actions.arn
}
