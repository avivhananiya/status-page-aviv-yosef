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
  identifier                = "${local.name_prefix}-db"
  engine                    = "postgres"
  engine_version            = "15"
  instance_class            = "db.t4g.medium"
  allocated_storage         = 50
  storage_type              = "gp3"
  db_name                   = "statuspage"
  username                  = "statuspage"
  password                  = random_password.db_password.result
  db_subnet_group_name      = aws_db_subnet_group.this.id
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = true
  publicly_accessible       = false
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-db-final-snapshot"
  backup_retention_period   = 7
  backup_window             = "03:00-04:00"
  storage_encrypted         = true
  apply_immediately         = true
  tags = {
    Name        = "${local.name_prefix}-db"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

# -------------------------
# RDS Security Group
# -------------------------
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

resource "aws_security_group_rule" "rds_proxy_to_rds" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_proxy.id
  source_security_group_id = aws_security_group.rds.id
  description              = "Allow RDS Proxy to connect to RDS on Postgres port"
}

resource "aws_security_group_rule" "rds_proxy_to_secrets_manager" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.rds_proxy.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS to AWS services (Secrets Manager)"
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
