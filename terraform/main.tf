locals {
  tags = {
    Project     = "boundary-worker"
    ManagedBy   = "terraform"
    ClusterName = var.cluster_name
  }
}

data "aws_caller_identity" "current" {}

# ── VPC ───────────────────────────────────────────────────────────────────────
# Public subnets: tagged for external NLBs (proxy service)
# Private subnets: worker nodes live here; tagged for internal LBs
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # Single NAT gateway — cost-effective for test/staging clusters.
  # Set single_nat_gateway = false for production to get per-AZ NAT gateways.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required subnet tags so the AWS Load Balancer Controller can discover
  # which subnets to provision NLBs/ALBs into.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.tags
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.k8s_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Public endpoint is required to run kubectl and helm from a workstation or CI.
  # Restrict access in production using cluster_endpoint_public_access_cidrs.
  cluster_endpoint_public_access = true

  # Enables the IAM OIDC identity provider — required for IRSA (pod-level IAM).
  enable_irsa = true

  # Grant the caller (the IAM entity running terraform apply) cluster-admin rights
  # so kubeconfig works immediately after apply without manual aws-auth patches.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    standard-workers = {
      instance_types = [var.node_type]
      desired_size   = var.node_desired
      min_size       = var.node_min
      max_size       = var.node_max

      # Disk size for worker nodes (GB)
      disk_size = 20
    }
  }

  tags = local.tags
}
