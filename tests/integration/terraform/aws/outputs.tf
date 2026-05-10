output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region the cluster was created in"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (used by IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for the EBS CSI driver"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

output "lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = module.lbc_irsa_role.iam_role_arn
}

output "kubeconfig_command" {
  description = "Run this command to update your local kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "eks_context" {
  description = "kubectl/helm context name for this cluster"
  value       = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
}

output "next_steps" {
  description = "Commands to run after terraform apply"
  value       = <<-EOT
    # 1. Update kubeconfig
    aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}

    # 2. Generate worker config
    make eks-worker-config

    # 3. Deploy boundary-worker Helm chart
    make eks-helm

    # 4. Run acceptance tests
    make eks-test

    # 5. Destroy all resources when done
    make tf-destroy
  EOT
}
