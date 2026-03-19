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
  type = list(string)
  default = []
  description = "Optional list of AZs. If empty, provider default AZs will be used (module will pick two)"
}

variable "enable_dns_failover" {
  type        = bool
  default     = false
  description = "Enable DNS failover records (requires ALB to exist). Set to true after K8s Ingress creates the ALB."
}
