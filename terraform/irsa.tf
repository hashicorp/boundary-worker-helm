# ── IRSA: Amazon EBS CSI Driver ───────────────────────────────────────────────
# Gives the ebs-csi-controller-sa service account permission to manage EBS volumes.
# The module attaches AWS-managed policy AmazonEBSCSIDriverPolicy automatically.
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "AmazonEKS_EBS_CSI_DriverRole_${var.cluster_name}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# ── IRSA: AWS Load Balancer Controller ────────────────────────────────────────
# Gives the aws-load-balancer-controller service account permission to manage
# ELBs, target groups, listeners, security groups, and WAF associations.
# The module creates and attaches the full LBC IAM policy automatically.
module "lbc_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "AWSLoadBalancerControllerRole_${var.cluster_name}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}
