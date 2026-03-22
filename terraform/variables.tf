variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = []
  description = "Optional list of AZs. If empty, provider default AZs will be used (module will pick two)"
}

variable "enable_dns_failover" {
  type        = bool
  default     = true
  description = "Enable DNS failover records (requires ALB to exist). Was default false during initial bootstrap before ALB existed."
}

variable "enable_sns_alerting" {
  type        = bool
  default     = false
  description = "Enable SNS topic + CloudWatch alarm for failover alerting. Requires SNS permissions (currently blocked by college IAM policy)."
}
