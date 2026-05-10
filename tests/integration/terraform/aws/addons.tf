# ── Amazon EBS CSI Driver addon ───────────────────────────────────────────────
# Enables dynamic provisioning of gp2 EBS volumes for PersistentVolumeClaims.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

  # OVERWRITE ensures Terraform stays authoritative over addon configuration.
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags

  depends_on = [module.eks]
}

# ── gp2 StorageClass ──────────────────────────────────────────────────────────
# Mirrors what eks-cluster-setup.sh creates manually.
# WaitForFirstConsumer prevents volumes from being provisioned before the pod
# is scheduled (avoids AZ mismatch issues).
resource "kubernetes_storage_class_v1" "gp2" {
  metadata {
    name = "gp2"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp2"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# ── AWS Load Balancer Controller ──────────────────────────────────────────────
# Required for the boundary-worker proxy service (type=LoadBalancer → NLB).
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version
  namespace  = "kube-system"

  # Reuse the service account created by the IRSA module (serviceAccount.create=false
  # so Helm does not overwrite the IRSA annotation set by Terraform).
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lbc_irsa_role.iam_role_arn
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    module.eks,
    module.lbc_irsa_role,
  ]
}
