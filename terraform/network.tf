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
