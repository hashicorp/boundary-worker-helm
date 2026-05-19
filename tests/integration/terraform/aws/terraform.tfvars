# Copyright IBM Corp. 2026

# Values are supplied via environment variables using the TF_VAR_* convention,
# or via the Makefile -var= flags (which read from the .env file at the repo root).
# Variables not set here fall back to the defaults defined in variables.tf.
#
# Required environment variables (set in .env or export before running make):
#
#   AWS_REGION                   → aws_region          (default: ap-south-1)
#   EKS_CLUSTER_NAME             → cluster_name        (default: boundary-k8s-cluster-1)
#   K8S_VERSION                  → k8s_version         (default: 1.31)
#   TF_NODE_TYPE                 → node_type           (default: t3.medium)
#   TF_NODE_DESIRED              → node_desired        (default: 2)
#   TF_NODE_MIN                  → node_min            (default: 1)
#   TF_NODE_MAX                  → node_max            (default: 3)
#   TF_AVAILABILITY_ZONES        → availability_zones  (default: ["ap-south-1a","ap-south-1b","ap-south-1c"])
#   TF_LBC_CHART_VERSION         → lbc_chart_version   (default: 1.8.1)
#   TF_ALLOWED_PUBLIC_ACCESS_CIDRS → allowed_public_access_cidrs (default: ["0.0.0.0/0"])
#
# To override on the command line without changing .env:
#   terraform apply -var="cluster_name=my-cluster" -var="aws_region=us-east-1"
