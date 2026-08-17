locals {
  github_owner         = "rajravichandrann"
  github_owner_id      = "42481430"
  github_repository    = "eks-sre-reference-platform"
  github_repository_id = "1336229988"

  github_main_subject = "repo:${local.github_owner}@${local.github_owner_id}/${local.github_repository}@${local.github_repository_id}:ref:refs/heads/main"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name = "github-actions"
  }
}

data "aws_iam_policy_document" "github_terraform_assume_role" {
  statement {
    sid     = "GitHubActionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        local.github_main_subject
      ]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name = "eks-sre-reference-github-terraform"

  assume_role_policy = data.aws_iam_policy_document.github_terraform_assume_role.json

  max_session_duration = 3600

  tags = {
    Name = "eks-sre-reference-github-terraform"
  }
}

data "aws_iam_policy_document" "github_terraform_permissions" {

  statement {
    sid    = "TerraformPlatformServices"
    effect = "Allow"

    actions = [
      "ec2:*",
      "eks:*",
      "ecr:*",
      "logs:*",
      "kms:*"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PassRole"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-sre-reference-*"
    ]
  }

  statement {
    sid    = "ReadIAMPolicies"
    effect = "Allow"

    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicies",
      "iam:ListRoles"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CreateRequiredServiceLinkedRoles"
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"

      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com"
      ]
    }
  }

  statement {
    sid    = "ReadTerraformStateBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"

      values = [
        "eks-sre-reference/dev/*"
      ]
    }
  }

  statement {
    sid    = "ManageTerraformState"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${aws_s3_bucket.terraform_state.arn}/eks-sre-reference/dev/terraform.tfstate",
      "${aws_s3_bucket.terraform_state.arn}/eks-sre-reference/dev/terraform.tfstate.tflock"
    ]
  }

  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_terraform" {
  name = "eks-sre-reference-terraform"
  role = aws_iam_role.github_terraform.id

  policy = data.aws_iam_policy_document.github_terraform_permissions.json
}