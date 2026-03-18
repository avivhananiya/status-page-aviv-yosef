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
# Redis Security Group
# -------------------------
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
