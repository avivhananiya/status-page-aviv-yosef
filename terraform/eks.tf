# -------------------------
# EKS Cluster (terraform-aws-modules/eks/aws)
# -------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name_prefix
  cluster_version = "1.35"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    spot = {
      name          = "spot-nodes"
      desired_size  = 3
      min_size      = 1
      max_size      = 4
      capacity_type = "SPOT"

      instance_types = ["t4g.large", "m6g.large"]
      ami_type       = "AL2023_ARM_64_STANDARD"
      disk_size      = 20

      key_name = null

      additional_security_group_ids = []

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = {
        "NodeGroup"   = "spot"
        "DoNotDelete" = "true"
      }
    }

    on_demand = {
      name          = "on-demand-nodes"
      desired_size  = 0
      min_size      = 0
      max_size      = 1
      capacity_type = "ON_DEMAND"

      instance_types = ["t4g.large", "m6g.large"]
      ami_type       = "AL2023_ARM_64_STANDARD"
      disk_size      = 20

      key_name = null

      additional_security_group_ids = []

      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = {
        "NodeGroup"   = "on-demand"
        "DoNotDelete" = "true"
      }
    }
  }

  enable_irsa = true

  cluster_addons = {
    coredns                         = { most_recent = true }
    kube-proxy                      = { most_recent = true }
    vpc-cni                         = { most_recent = true }
    amazon-cloudwatch-observability = { most_recent = true }
  }

  tags = {
    "Name"        = "${local.name_prefix}-eks"
    "Environment" = var.env
    "ManagedBy"   = "terraform"
  }
}

# Expose some module outputs via locals for later use
locals {
  eks_node_sg_id          = module.eks.node_security_group_id
  eks_cluster_oidc_issuer = module.eks.cluster_oidc_issuer_url
}

# Allow all traffic from VPC to EKS nodes
resource "aws_security_group_rule" "eks_allow_internal_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = local.eks_node_sg_id
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "Allow all traffic from VPC to EKS nodes"
}
