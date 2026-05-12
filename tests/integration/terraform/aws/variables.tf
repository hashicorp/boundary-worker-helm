# Copyright IBM Corp. 2026

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "boundary-k8s-cluster-1"
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "availability_zones" {
  description = "Availability zones for VPC subnets (must have at least 2)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "lbc_chart_version" {
  description = "Helm chart version for the AWS Load Balancer Controller (v2.9.x = chart 1.8.x)"
  type        = string
  default     = "1.8.1"
}

variable "allowed_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the EKS public API endpoint.
    Defaults to ["0.0.0.0/0"] so any workstation or CI runner can call kubectl
    without extra configuration. For production, restrict this to your office
    egress IP, VPN CIDR, or GitHub Actions IP ranges.
    Example: ["203.0.113.0/24", "198.51.100.42/32"]
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
