#!/bin/bash
# ============================================================================
# EKS Cluster Setup for Boundary Worker Helm Chart Acceptance Testing
#
# This script creates a production-ready EKS cluster with all prerequisites
# needed to run the Boundary Worker Helm chart:
#   - EKS cluster (via eksctl)
#   - OIDC provider (for IRSA)
#   - Amazon EBS CSI Driver (for gp2 PersistentVolumes)
#   - AWS Load Balancer Controller (for NLB proxy service)
#
# Required tools: aws, eksctl, kubectl, helm
#
# Required env vars:
#   AWS_REGION         - AWS region (e.g. us-east-1)
#   EKS_CLUSTER_NAME   - Name for the EKS cluster
#
# Optional env vars:
#   EKS_K8S_VERSION    - Kubernetes version (default: 1.31)
#   EKS_NODE_TYPE      - EC2 instance type  (default: t3.medium)
#   EKS_NODE_COUNT     - Desired node count  (default: 2)
#   EKS_NODE_MIN       - Minimum node count  (default: 1)
#   EKS_NODE_MAX       - Maximum node count  (default: 3)
#   LBC_VERSION        - AWS Load Balancer Controller version (default: v2.9.0)
# ============================================================================

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
pass() { echo "   ✅ $1"; }
fail() { echo "❌ FAILED: $1"; exit 1; }
info() { echo "   $1"; }
warn() { echo "⚠️ WARN: $1"; }
section() {
    echo ""
    echo "$1"
}

# ── Config ────────────────────────────────────────────────────────────────────
: "${AWS_REGION:?'AWS_REGION must be set (e.g. us-east-1)'}"
: "${EKS_CLUSTER_NAME:?'EKS_CLUSTER_NAME must be set'}"

K8S_VERSION="${EKS_K8S_VERSION:-1.31}"
NODE_TYPE="${EKS_NODE_TYPE:-t3.medium}"
NODE_COUNT="${EKS_NODE_COUNT:-2}"
NODE_MIN="${EKS_NODE_MIN:-1}"
NODE_MAX="${EKS_NODE_MAX:-3}"
LBC_VERSION="${LBC_VERSION:-v2.9.0}"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
section "Checking Prerequisites"

for tool in aws eksctl kubectl helm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "'$tool' not found. Install it before running this script."
    fi
    info "$tool: $(command -v "$tool")"
done

# Validate AWS credentials and capture account ID in one call
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || fail "AWS credentials are not configured. Run 'aws configure' or set AWS_PROFILE."
pass "AWS credentials valid — account: ${AWS_ACCOUNT_ID}, region: ${AWS_REGION}"

# ── 2. Create EKS Cluster ─────────────────────────────────────────────────────
section "Creating EKS Cluster: ${EKS_CLUSTER_NAME}"

if eksctl get cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    warn "Cluster '${EKS_CLUSTER_NAME}' already exists — skipping creation"
else
    info "Creating cluster (this takes ~15 minutes)..."
    eksctl create cluster \
        --name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --version "${K8S_VERSION}" \
        --nodegroup-name standard-workers \
        --node-type "${NODE_TYPE}" \
        --nodes "${NODE_COUNT}" \
        --nodes-min "${NODE_MIN}" \
        --nodes-max "${NODE_MAX}" \
        --with-oidc \
        --asg-access \
        --external-dns-access \
        --full-ecr-access \
        --managed
    pass "EKS cluster created"
fi

# Update kubeconfig
info "Updating kubeconfig..."
aws eks update-kubeconfig \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}"
pass "kubeconfig updated"

EKS_CONTEXT="arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"

# Verify cluster access
kubectl cluster-info --context "${EKS_CONTEXT}" >/dev/null 2>&1 \
    || fail "Cannot reach cluster '${EKS_CLUSTER_NAME}' after kubeconfig update"
pass "Cluster is accessible"

# ── 3. OIDC Provider ──────────────────────────────────────────────────────────
section "Configuring OIDC Provider (IRSA)"

eksctl utils associate-iam-oidc-provider \
    --region "${AWS_REGION}" \
    --cluster "${EKS_CLUSTER_NAME}" \
    --approve 2>&1 | tail -3

OIDC_ID=$(aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query "cluster.identity.oidc.issuer" \
    --output text | sed 's|.*/||')
[ -n "${OIDC_ID}" ] || fail "Failed to retrieve OIDC provider ID"
pass "OIDC provider configured: ${OIDC_ID}"

# ── 4. Amazon EBS CSI Driver ──────────────────────────────────────────────────
section "Installing Amazon EBS CSI Driver"

# Create IAM role for EBS CSI
if aws iam get-role --role-name "AmazonEKS_EBS_CSI_DriverRole_${EKS_CLUSTER_NAME}" >/dev/null 2>&1; then
    warn "EBS CSI IAM role already exists — skipping"
else
    info "Creating IAM service account for EBS CSI driver..."
    eksctl create iamserviceaccount \
        --name ebs-csi-controller-sa \
        --namespace kube-system \
        --cluster "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --role-name "AmazonEKS_EBS_CSI_DriverRole_${EKS_CLUSTER_NAME}" \
        --role-only \
        --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
        --approve
    pass "EBS CSI IAM role created"
fi

EBS_CSI_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_${EKS_CLUSTER_NAME}"

# Install or update EBS CSI addon
if aws eks describe-addon \
        --cluster-name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --addon-name aws-ebs-csi-driver >/dev/null 2>&1; then
    warn "aws-ebs-csi-driver addon already installed — skipping"
else
    info "Installing aws-ebs-csi-driver addon..."
    aws eks create-addon \
        --cluster-name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --addon-name aws-ebs-csi-driver \
        --service-account-role-arn "${EBS_CSI_ROLE_ARN}"
    info "Waiting for EBS CSI addon to become active..."
    aws eks wait addon-active \
        --cluster-name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --addon-name aws-ebs-csi-driver
    pass "EBS CSI driver addon active"
fi

# Ensure gp2 StorageClass exists with WaitForFirstConsumer
if ! kubectl get storageclass gp2 --context "${EKS_CONTEXT}" >/dev/null 2>&1; then
    warn "gp2 StorageClass not found — creating..."
    kubectl apply --context "${EKS_CONTEXT}" -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp2
  encrypted: "true"
EOF
    pass "gp2 StorageClass created"
else
    pass "gp2 StorageClass already exists"
fi

# ── 5. AWS Load Balancer Controller ───────────────────────────────────────────
section "Installing AWS Load Balancer Controller"

LBC_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy_${EKS_CLUSTER_NAME}"

# Create IAM policy for LBC if it does not exist
if aws iam get-policy \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LBC_POLICY_NAME}" \
        >/dev/null 2>&1; then
    warn "LBC IAM policy already exists — skipping creation"
else
    info "Downloading LBC IAM policy document (${LBC_VERSION})..."
    curl -fsSLo /tmp/lbc-iam-policy.json \
        "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"

    aws iam create-policy \
        --policy-name "${LBC_POLICY_NAME}" \
        --policy-document file:///tmp/lbc-iam-policy.json \
        --region "${AWS_REGION}" \
        --output text --query 'Policy.Arn' >/dev/null
    rm -f /tmp/lbc-iam-policy.json
    pass "LBC IAM policy created"
fi

LBC_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LBC_POLICY_NAME}"

# Create IAM service account for LBC
if kubectl get serviceaccount aws-load-balancer-controller \
        -n kube-system --context "${EKS_CONTEXT}" >/dev/null 2>&1; then
    warn "LBC service account already exists — skipping"
else
    info "Creating IAM service account for LBC..."
    eksctl create iamserviceaccount \
        --cluster "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}" \
        --namespace kube-system \
        --name aws-load-balancer-controller \
        --attach-policy-arn "${LBC_POLICY_ARN}" \
        --override-existing-serviceaccounts \
        --approve
    pass "LBC IAM service account created"
fi

# Install LBC via Helm
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update eks 2>/dev/null || true

VPC_ID=$(aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)
[ -n "${VPC_ID}" ] || fail "Failed to retrieve VPC ID for cluster '${EKS_CLUSTER_NAME}'"

if helm status aws-load-balancer-controller -n kube-system \
        --kube-context "${EKS_CONTEXT}" >/dev/null 2>&1; then
    warn "AWS Load Balancer Controller already installed — skipping"
else
    info "Installing AWS Load Balancer Controller..."
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --namespace kube-system \
        --kube-context "${EKS_CONTEXT}" \
        --set clusterName="${EKS_CLUSTER_NAME}" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region="${AWS_REGION}" \
        --set vpcId="${VPC_ID}" \
        --timeout 5m
    pass "AWS Load Balancer Controller installed"
fi

# Wait for LBC to be ready
info "Waiting for LBC deployment to be available..."
kubectl wait --for=condition=available \
    --timeout=120s \
    deployment/aws-load-balancer-controller \
    -n kube-system \
    --context "${EKS_CONTEXT}" >/dev/null 2>&1 \
    || fail "AWS Load Balancer Controller did not become available in time"
pass "AWS Load Balancer Controller is ready"

# ── Summary ───────────────────────────────────────────────────────────────────
section "EKS Cluster Setup Complete"

echo ""
echo "Cluster:   ${EKS_CLUSTER_NAME}"
echo "Region:    ${AWS_REGION}"
echo "Context:   ${EKS_CONTEXT}"
echo "Nodes:"
kubectl get nodes --context "${EKS_CONTEXT}" \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,VERSION:.status.nodeInfo.kubeletVersion'
echo ""
echo "Add-ons ready:"
echo "  - Amazon EBS CSI Driver (gp2 storage)"
echo "  - AWS Load Balancer Controller (NLB support)"
echo ""
echo "Next steps:"
echo "  export EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}"
echo "  export AWS_REGION=${AWS_REGION}"
echo "  make eks-worker-config    # Generate worker.hcl"
echo "  make eks-helm             # Deploy Helm chart"
echo "  make eks-test             # Run acceptance tests"
