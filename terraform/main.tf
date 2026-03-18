data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "yosef-aviv-status-page-${var.env}"
  domain_name = "yosef-aviv-statuspage.xyz"
}

# -------------------------
# VPC (terraform-aws-modules/vpc/aws)
# -------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name_prefix
  cidr = var.vpc_cidr

  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  database_subnets= ["10.0.20.0/24", "10.0.21.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true

  tags = {
    "Name"        = "${local.name_prefix}-vpc"
    "Environment" = var.env
    "ManagedBy"   = "terraform"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# -------------------------
# S3 Gateway Endpoint (free — removes S3 traffic from NAT)
# -------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"

  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name        = "${local.name_prefix}-s3-endpoint"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# EKS Cluster (terraform-aws-modules/eks/aws)
# -------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name_prefix
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access          = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    spot = {
      name           = "spot-nodes"
      desired_size   = 3
      min_size       = 0
      max_size       = 4
      capacity_type  = "SPOT"

      instance_types = ["t4g.medium", "t4g.small", "m6g.medium"]
      ami_type       = "AL2_ARM_64"
      disk_size      = 20

      key_name = null

      additional_security_group_ids = []

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = {
        "NodeGroup" = "spot"
      }
    }

    on_demand = {
      name           = "on-demand-nodes"
      desired_size   = 0
      min_size       = 0
      max_size       = 1
      capacity_type  = "ON_DEMAND"

      instance_types = ["t4g.medium", "m6g.medium"]
      ami_type       = "AL2_ARM_64"
      disk_size      = 20

      key_name = null

      additional_security_group_ids = []

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = {
        "NodeGroup" = "on-demand"
      }
    }
  }

  enable_irsa = true

  cluster_addons = {
    "amazon-cloudwatch-observability" = {
      most_recent = true
    }
  }

  tags = {
    "Name"        = "${local.name_prefix}-eks"
    "Environment" = var.env
    "ManagedBy"   = "terraform"
  }
}

# Expose some module outputs via locals for later use
locals {
  eks_node_sg_id = module.eks.node_security_group_id
  eks_cluster_oidc_issuer = module.eks.cluster_oidc_issuer_url
}

# -------------------------
# Random secrets
# -------------------------
resource "random_password" "db_password" {
  length           = 16
  override_special = "#%&*()-_+=<>?"
  special          = true
}

resource "random_string" "redis_token" {
  length  = 24
  lower   = true
  upper   = true
  numeric = true
  special = false  # only alphanumeric characters to satisfy ElastiCache validation
}

# django secret key to be stored in Secrets Manager
resource "random_password" "django_secret_key" {
  length           = 50
  override_special = "@#%&*()-_+=<>?"
  special          = true
}

# -------------------------
# RDS Subnet Group
# -------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = module.vpc.database_subnets
  tags = {
    Name        = "${local.name_prefix}-db-subnet-group"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# RDS Instance (Postgres)
# -------------------------
resource "aws_db_instance" "postgres" {
  identifier               = "${local.name_prefix}-db"
  engine                   = "postgres"
  engine_version           = "15"
  instance_class           = "db.t4g.medium"
  allocated_storage        = 50
  storage_type             = "gp3"
  db_name                  = "statuspage"
  username                 = "statuspage"
  password                 = random_password.db_password.result
  db_subnet_group_name     = aws_db_subnet_group.this.id
  vpc_security_group_ids   = [aws_security_group.rds.id]
  multi_az                    = true
  publicly_accessible         = false
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${local.name_prefix}-db-final-snapshot"
  backup_retention_period     = 7
  backup_window               = "03:00-04:00"
  storage_encrypted           = true
  apply_immediately           = true
  tags = {
    Name        = "${local.name_prefix}-db"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# RDS Proxy
# -------------------------
resource "aws_security_group" "rds_proxy" {
  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "RDS Proxy SG - allow access from EKS nodes"
  vpc_id      = module.vpc.vpc_id
  tags = {
    Name        = "${local.name_prefix}-rds-proxy-sg"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "rds_proxy_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_proxy.id
  source_security_group_id = local.eks_node_sg_id
  description              = "Allow Postgres from EKS nodes to RDS Proxy"
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${local.name_prefix}-rds-proxy-role"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "${local.name_prefix}-rds-proxy-secrets"
  role = aws_iam_role.rds_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.db_secret.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_db_proxy" "this" {
  name                   = "${local.name_prefix}-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = false
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = module.vpc.database_subnets

  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy auth via Secrets Manager"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_secret.arn
  }

  tags = {
    Name        = "${local.name_prefix}-proxy"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = aws_db_instance.postgres.identifier
}

# -------------------------
# ElastiCache Subnet Group
# -------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis-subnet-group"
  subnet_ids = module.vpc.database_subnets
  tags = {
    Name        = "${local.name_prefix}-redis-subnet-group"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# ElastiCache (Redis)
# -------------------------
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${local.name_prefix}-redis"
  description                   = "Status Page Redis (${var.env})"
  engine                        = "redis"
  node_type                     = "cache.t4g.micro"
  num_cache_clusters            = 2
  automatic_failover_enabled    = true
  transit_encryption_enabled    = true
  at_rest_encryption_enabled    = true
  port                          = 6379
  subnet_group_name             = aws_elasticache_subnet_group.this.name
  security_group_ids            = [aws_security_group.redis.id]
  auth_token                    = random_string.redis_token.result
  apply_immediately             = true
  tags = {
    Name        = "${local.name_prefix}-redis"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# Security Groups
# -------------------------
# EKS Nodes security group is created by module.eks; ensure it allows ingress only from VPC CIDR
resource "aws_security_group_rule" "eks_allow_internal_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = local.eks_node_sg_id
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "Allow all traffic from VPC to EKS nodes"
}

# RDS security group - allow ingress from RDS Proxy only
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS SG - allow access from RDS Proxy"
  vpc_id      = module.vpc.vpc_id
  tags = {
    Name        = "${local.name_prefix}-rds-sg"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "rds_from_proxy" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.rds_proxy.id
  description              = "Allow Postgres from RDS Proxy"
}

# Redis security group - allow ingress from EKS nodes security group only
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis SG - allow access from EKS nodes"
  vpc_id      = module.vpc.vpc_id
  tags = {
    Name        = "${local.name_prefix}-redis-sg"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "redis_from_eks" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = local.eks_node_sg_id
  description              = "Allow Redis from EKS nodes"
}

# -------------------------
# Secrets Manager - store only sensitive values (DB password, Redis auth token, Django secret key)
# -------------------------
resource "aws_secretsmanager_secret" "db_secret" {
  name = "${local.name_prefix}-db-credentials-v2"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-db-credentials-v2"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "statuspage",
    password = random_password.db_password.result
  })
}

resource "aws_secretsmanager_secret" "redis_secret" {
  name = "${local.name_prefix}-redis-auth-v2"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-redis-auth-v2"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "redis_secret_version" {
  secret_id     = aws_secretsmanager_secret.redis_secret.id
  secret_string = jsonencode({
    auth_token = random_string.redis_token.result
  })
}

resource "aws_secretsmanager_secret" "django_secret" {
  name = "${local.name_prefix}-django-secret-key"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-django-secret-key"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "django_secret_version" {
  secret_id     = aws_secretsmanager_secret.django_secret.id
  secret_string = jsonencode({
    secret_key = random_password.django_secret_key.result
  })
}

# -------------------------
# IAM Policy & Role for IRSA (read-only access to the specific secrets)
# -------------------------
# Due to variations in module outputs for OIDC URL, build a standard assume policy using the OIDC provider


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
# IAM Role for AWS Load Balancer Controller (IRSA)
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
# Helm Releases (ALB Controller & CSI Driver)
# -------------------------
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}

resource "helm_release" "csi_secrets_store" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.4.2"

  set {
    name  = "syncSecret.enabled"
    value = "false"
  }

  depends_on = [module.eks]
}

resource "helm_release" "csi_secrets_store_provider_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.8"

  depends_on = [helm_release.csi_secrets_store]
}

# -------------------------
# S3 Bucket for Static Files
# -------------------------

# Generate random suffix for bucket name uniqueness
resource "random_string" "s3_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create S3 bucket for static files
resource "aws_s3_bucket" "static_files" {
  bucket = "status-page-yosef-aviv-${random_string.s3_suffix.result}"

  tags = {
    Name        = "${local.name_prefix}-static-files"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# Block all public access settings (set to false to allow public read)
resource "aws_s3_bucket_public_access_block" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for public read access to static files
resource "aws_s3_bucket_policy" "static_files" {
  bucket = aws_s3_bucket.static_files.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_files.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_files]
}

# -------------------------
# ECR Repository for Application Images
# -------------------------
resource "aws_ecr_repository" "app" {
  name                 = local.name_prefix
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = true 
}

# ==========================================
# ACM Certificate & DNS Validation
# ==========================================

data "aws_route53_zone" "main" {
  name         = local.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "cert" {
  domain_name               = local.domain_name
  subject_alternative_names = ["*.${local.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${local.name_prefix}-cert"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==========================================
# DNS Failover — S3 Static Page + Route 53 + Alerting
# ==========================================
# NOTE: data.aws_lb requires the ALB to exist (created by the
#       AWS Load Balancer Controller when the Ingress is applied).
#       On first deploy: apply Terraform, then kubectl apply -k k8s/,
#       then terraform apply again to create the failover records.

data "aws_lb" "alb" {
  name = "status-page-alb"
}

# S3 bucket for failover page (bucket name must match domain for Route 53 Alias)
resource "aws_s3_bucket" "failover_page" {
  bucket = local.domain_name
  tags = {
    Name        = "${local.name_prefix}-failover-page"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "failover_page" {
  bucket = aws_s3_bucket.failover_page.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.failover_page.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.failover_page]
}

resource "aws_s3_object" "failover_index" {
  bucket       = aws_s3_bucket.failover_page.id
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Status Page</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          margin: 0;
          background: #f5f5f5;
          color: #333;
        }
        .container {
          text-align: center;
          max-width: 500px;
          padding: 2rem;
        }
        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
        p { color: #666; line-height: 1.6; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>We are investigating</h1>
        <p>Our status page is temporarily unavailable. The team has been
        notified and is working to restore service. Please check back shortly.</p>
      </div>
    </body>
    </html>
  HTML
}

# Route 53 Failover: Primary (ALB) → Secondary (S3 static page)
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = data.aws_lb.alb.dns_name
    zone_id                = data.aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = aws_s3_bucket_website_configuration.failover_page.website_domain
    zone_id                = aws_s3_bucket.failover_page.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 health check for CloudWatch alerting
resource "aws_route53_health_check" "alb" {
  fqdn              = data.aws_lb.alb.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "${local.name_prefix}-alb-health"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# SNS topic for failover alerting
resource "aws_sns_topic" "failover_alert" {
  name = "${local.name_prefix}-failover-alert"
  tags = {
    Name        = "${local.name_prefix}-failover-alert"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# CloudWatch alarm: triggers when Route 53 health check fails
resource "aws_cloudwatch_metric_alarm" "failover" {
  alarm_name          = "${local.name_prefix}-failover-alert"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Status Page ALB health check failed — DNS failover activated"
  alarm_actions       = [aws_sns_topic.failover_alert.arn]
  ok_actions          = [aws_sns_topic.failover_alert.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.alb.id
  }

  tags = {
    Name        = "${local.name_prefix}-failover-alarm"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# Cluster Autoscaler (IRSA & Helm Release)
# -------------------------
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  tags = {
    Name        = "${local.name_prefix}-cluster-autoscaler-irsa"
    Environment = var.env
    ManagedBy   = "terraform"
  }
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
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_autoscaler_irsa.iam_role_arn
  }
  depends_on = [module.eks]
}


# -------------------------
# Metrics Server (Required for HPA)
# -------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  set {
    name  = "metrics.enabled"
    value = "true"
  }

  depends_on = [module.eks]
}

# ------------------------------------------------------
# AWS Systems Manager (SSM) Parameters
# ------------------------------------------------------

resource "aws_ssm_parameter" "db_host" {
  name  = "/${local.name_prefix}/db/host"
  type  = "String"
  value = aws_db_proxy.this.endpoint
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "/${local.name_prefix}/redis/host"
  type  = "String"
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

resource "aws_ssm_parameter" "s3_static_url" {
  name  = "/${local.name_prefix}/s3/static_url"
  type  = "String"
  value = "https://${aws_s3_bucket.static_files.bucket_regional_domain_name}"
}

# ------------------------------------------------------
# IAM POLICY to read the SSM Parameters
# ------------------------------------------------------

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

# ------------------------------------------------------
# Install External Secrets Operator via Helm
# ------------------------------------------------------
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  version          = "0.12.1"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# ------------------------------------------------------
# Install ArgoCD via Helm
# ------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"

  set {
    name  = "server.service.type"
    value = "NodePort"
  }

  depends_on = [module.eks]
}

# ------------------------------------------------------
# AWS WAF v2 — Web Application Firewall
# Attached to the ALB via Ingress annotation:
#   alb.ingress.kubernetes.io/wafv2-acl-arn
# ------------------------------------------------------
resource "aws_wafv2_web_acl" "this" {
  name        = "${local.name_prefix}-waf"
  description = "WAF for Status Page ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Common Rule Set (XSS, bad bots, etc.)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: SQL Injection Rule Set
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known Bad Inputs Rule Set
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${local.name_prefix}-waf"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------
# ExternalDNS (IRSA & Helm Release)
# ------------------------------------------------------

# create IAM role for ExternalDNS (IRSA)

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                  = "${local.name_prefix}-external-dns"
  attach_external_dns_policy = true
  
  external_dns_hosted_zone_arns = [data.aws_route53_zone.main.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = {
    Name        = "${local.name_prefix}-external-dns-irsa"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# installing ExternalDNS via Helm

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "1.14.4"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "txtOwnerId"
    value = local.name_prefix
  }

  set {
    name  = "domainFilters[0]"
    value = local.domain_name
  }
  
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_dns_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}
