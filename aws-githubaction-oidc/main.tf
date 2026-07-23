locals {
  github_repo = [
    { user = "akhileshmishrabiz", repo = "k8s-bootcamp-dec25", branches = ["main"], tags = false, wildcard = false },
    { user = "akhileshmishrabiz", repo = "k8sbootcamp-march26", branches = [], tags = false, wildcard = true },
    { user = "akhileshmishrabiz", repo = "k8s-may26", branches = ["main"], tags = true, wildcard = false },
  ]

  # branch refs  -> repo:OWNER/REPO:ref:refs/heads/<branch>
  # tag refs     -> repo:OWNER/REPO:ref:refs/tags/*  (prod workflow on tag push)
  # wildcard     -> repo:OWNER/REPO:*
  github_oidc_subjects = distinct(flatten([
    for r in local.github_repo : r.wildcard ? ["repo:${r.user}/${r.repo}:*"] : concat(
      [for b in r.branches : "repo:${r.user}/${r.repo}:ref:refs/heads/${b}"],
      r.tags ? ["repo:${r.user}/${r.repo}:ref:refs/tags/*"] : []
    )
  ]))
}



# create IAM inentity provider for github -> aws IAM 
# create iam policy that allow users to talkk to ecr 
# iam role that allow the web idnity to assukme this role 
# and attach the iam policy for ecr to this role. 
# on github -> use that role instead of keys


resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  #   thumbprint_list = [
  #     "6938fd4d98bab03faadb97b34396831e3780aea1"
  #   ]

  tags = {
    Name = "AWS-GH-march26"
  }
}

resource "aws_iam_role" "aws-github-oidc-march26" {
  name = "aws-github-oidc-march26"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subjects
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "GitHub-Actions-aws-marc26"
  }
}

resource "aws_iam_role_policy_attachment" "attach_ecr_policy" {
  role       = aws_iam_role.aws-github-oidc-march26.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


output "aws_iam_role_arn" {
  value = aws_iam_role.aws-github-oidc-march26.arn
}