# -------------------------
# Random Secrets
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
  special = false # only alphanumeric characters to satisfy ElastiCache validation
}

resource "random_password" "django_secret_key" {
  length           = 50
  override_special = "@#%&*()-_+=<>?"
  special          = true
}

# -------------------------
# Secrets Manager — DB Credentials
# -------------------------
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "${local.name_prefix}-db-credentials-v2"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-db-credentials-v2"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "statuspage",
    password = random_password.db_password.result
  })
}

# -------------------------
# Secrets Manager — Redis Auth Token
# -------------------------
resource "aws_secretsmanager_secret" "redis_secret" {
  name                    = "${local.name_prefix}-redis-auth-v2"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-redis-auth-v2"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "redis_secret_version" {
  secret_id = aws_secretsmanager_secret.redis_secret.id
  secret_string = jsonencode({
    auth_token = random_string.redis_token.result
  })
}

# -------------------------
# Secrets Manager — Django Secret Key
# -------------------------
resource "aws_secretsmanager_secret" "django_secret" {
  name                    = "${local.name_prefix}-django-secret-key"
  recovery_window_in_days = 0
  tags = {
    Name        = "${local.name_prefix}-django-secret-key"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "django_secret_version" {
  secret_id = aws_secretsmanager_secret.django_secret.id
  secret_string = jsonencode({
    secret_key = random_password.django_secret_key.result
  })
}
