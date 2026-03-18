# -------------------------
# IRSA — Application Pod Role (Secrets Manager + SSM access)
# -------------------------
data "aws_iam_policy_document" "irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:status-page-sa"]
    }
  }
}

resource "aws_iam_role" "irsa_role" {
  name               = "${local.name_prefix}-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role.json
  tags = {
    Name        = "${local.name_prefix}-irsa-role"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "secrets_read_policy_doc" {
  statement {
    sid    = "AllowReadSpecificSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]

    resources = [
      aws_secretsmanager_secret.db_secret.arn,
      aws_secretsmanager_secret.redis_secret.arn,
      aws_secretsmanager_secret.django_secret.arn
    ]
  }
}

resource "aws_iam_policy" "secrets_read_policy" {
  name   = "${local.name_prefix}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "attach_secrets_policy" {
  role       = aws_iam_role.irsa_role.name
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

# -------------------------
# IRSA — SSM Parameter Store Read Access
# -------------------------
resource "aws_iam_policy" "ssm_read_policy" {
  name        = "${local.name_prefix}-ssm-read-policy"
  description = "Allow EKS pods to read infrastructure endpoints from SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_ssm_attach" {
  role       = aws_iam_role.irsa_role.name
  policy_arn = aws_iam_policy.ssm_read_policy.arn
}

# -------------------------
# IRSA — AWS Load Balancer Controller
# -------------------------
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.name_prefix}-alb-controller-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Name        = "${local.name_prefix}-alb-controller-irsa"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# IRSA — Cluster Autoscaler
# -------------------------
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${local.name_prefix}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = {
    Name        = "${local.name_prefix}-cluster-autoscaler-irsa"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

