resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:pull_request"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_terraform" {
  name               = "${var.github_repo}-github-actions-terraform-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "terraform_plan_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${var.terraform_state_bucket}",
      "arn:aws:s3:::${var.terraform_state_bucket}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      "arn:aws:dynamodb:${var.aws_region}:*:table/${var.terraform_lock_table}"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "s3:ListAllMyBuckets",
      "s3:GetBucket*",
      "s3:ListBucket",
      "iam:Get*",
      "iam:List*"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions_terraform_plan" {
  name   = "${var.github_repo}-github-actions-terraform-plan-policy"
  policy = data.aws_iam_policy_document.terraform_plan_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_plan" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = aws_iam_policy.github_actions_terraform_plan.arn
}