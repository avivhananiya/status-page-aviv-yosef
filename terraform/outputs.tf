output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_public_subnets" {
  value = module.vpc.public_subnets
}

output "vpc_private_subnets" {
  value = module.vpc.private_subnets
}

output "rds_endpoint" {
  description = "Direct RDS instance endpoint (for debugging only)"
  value       = aws_db_instance.postgres.address
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (used by application pods)"
  value       = aws_db_proxy.this.endpoint
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}


output "app_irsa_role_arn" {
  description = "ARN of the IAM role for the application pods to access secrets"
  value       = aws_iam_role.irsa_role.arn
}

output "alb_controller_irsa_role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller"
  value       = module.alb_controller_irsa.iam_role_arn
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}


output "s3_static_url" {
  description = "HTTPS URL for S3 static files bucket"
  value       = "https://${aws_s3_bucket.static_files.bucket_regional_domain_name}"
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN — use in Ingress annotation: alb.ingress.kubernetes.io/wafv2-acl-arn"
  value       = aws_wafv2_web_acl.this.arn
}