# -------------------------
# SSM Parameters — Infrastructure Endpoints
# -------------------------
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
