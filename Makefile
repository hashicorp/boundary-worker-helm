# Copyright IBM Corp. 2026

# Auto-load .env if present (strips 'export ' prefix for Make compatibility)
ifneq (,$(wildcard .env))
  $(shell sed 's/^export //; /^[[:space:]]*#/d; /^$$/d' .env > .env.make)
  include .env.make
  export
endif

# Chart source for cloud install targets.
# Supports local path (.), packaged chart URL, or repo/chart reference.
HELM_CHART ?= .
# Required only when HELM_CHART is a repo/chart reference.
HELM_CHART_VERSION ?=

# ================================
# PHONY Declarations
# ================================
.PHONY: help format deps clean lint test unit-test worker-config
.PHONY: setup-helm setup-kubeconform setup-trivy setup-kubescape setup-helm-unittest lint-helm-k8s trivy-scan kubescape-scan
.PHONY: acceptance-setup acceptance-cluster acceptance-helm acceptance-test acceptance-full acceptance-cleanup
.PHONY: kind-matrix-test kind-matrix-cleanup
.PHONY: eks-setup eks-helm eks-test eks-full eks-cleanup
.PHONY: tf-setup tf-destroy tf-output tf-plan
.PHONY: aks-setup aks-helm aks-test aks-full aks-cleanup
.PHONY: tf-setup-aks tf-plan-aks tf-destroy-aks tf-output-aks
.PHONY: gke-setup gke-helm gke-test gke-full gke-cleanup
.PHONY: tf-setup-gke tf-plan-gke tf-destroy-gke tf-output-gke

# ================================
# Help Target
# ================================
help:
	@echo "================================"
	@echo "Boundary Worker Helm Chart - Lint Targets"
	@echo "================================"
	@echo "Available targets:"
	@echo "  make format            - Format all YAML files with Prettier"
	@echo "  make deps              - Install required tools (macOS)"
	@echo "  make lint              - Run all lints and scans locally (deps + lint + scans)"
	@echo "  make test              - Run unit tests (alias for unit-test)"
	@echo "  make unit-test         - Run Helm unit tests with helm-unittest"
	@echo "  make clean             - Clean generated files"
	@echo "  make worker-config          - Authenticate, create a worker, and generate worker.hcl"
	@echo ""
	@echo "CI/CD targets:"
	@echo "  make setup-helm         - Install Helm for CI"
	@echo "  make setup-helm-unittest - Install helm-unittest plugin for CI"
	@echo "  make setup-kubeconform  - Install Kubeconform for CI"
	@echo "  make setup-trivy        - Install Trivy for CI"
	@echo "  make setup-kubescape    - Install Kubescape for CI"
	@echo "  make lint-helm-k8s      - Run Helm lint, render templates, and K8s validation"
	@echo "  make trivy-scan         - Run security scan with Trivy"
	@echo "  make kubescape-scan     - Run security scan with Kubescape"
	@echo ""
	@echo "Acceptance Testing targets:"
	@echo "  make acceptance-setup   - Install dependencies and setup KIND cluster"
	@echo "  make acceptance-helm    - Install Helm chart from worker.hcl and run Helm tests"
	@echo "  make acceptance-test    - Run acceptance tests"
	@echo "  make acceptance-full    - Run full acceptance workflow (setup + worker-config + helm + tests)"
	@echo "  make acceptance-cleanup    - Delete acceptance cluster"
	@echo "  make kind-matrix-test      - Run tcp-target-conn-test.sh across the 2 KIND versions prior to latest (auto-resolved)"
	@echo "  make kind-matrix-cleanup   - Delete the acceptance cluster and cached KIND binaries"
	@echo ""
	@echo "AWS EKS Acceptance Testing targets (shell-based, legacy):"
	@echo "  make eks-setup             - Provision EKS cluster via Terraform (tf-setup)"
	@echo "  make eks-helm              - Install Helm chart with EKS values (gp3, NLB)"
	@echo "  make eks-test              - Run full EKS acceptance test suite"
	@echo "  make eks-full              - Full EKS workflow (eks-setup + worker-config + helm + test)"
	@echo "  make eks-cleanup           - Uninstall Helm release from EKS (set DESTROY_CLUSTER=true to delete cluster)"
	@echo "                               Optional: HELM_CHART=<local path|chart tgz URL|repo/chart> (default: .)"
	@echo "                               Optional: HELM_CHART_VERSION=<chart version> (required with repo/chart)"
	@echo ""
	@echo "Terraform EKS targets (recommended):"
	@echo "  make tf-setup              - terraform init + apply (VPC + EKS + EBS CSI + LBC)"
	@echo "  make tf-plan               - terraform plan (preview changes without applying)"
	@echo "  make tf-destroy            - terraform destroy (tear down ALL AWS resources cleanly)"
	@echo "  make tf-output             - Show terraform outputs (cluster name, kubeconfig cmd, etc.)"
	@echo ""
	@echo "Azure AKS Integration Testing targets:"
	@echo "  make aks-setup             - Provision AKS cluster via Terraform (tf-setup-aks)"
	@echo "  make aks-helm              - Install Helm chart with AKS values (managed-csi-premium, LoadBalancer)"
	@echo "  make aks-test              - Run full AKS integration test suite"
	@echo "  make aks-full              - Full AKS workflow (aks-setup + worker-config + helm + test)"
	@echo "  make aks-cleanup           - Uninstall Helm release from AKS (set DESTROY_CLUSTER=true to delete cluster)"
	@echo "                               Optional: HELM_CHART=<local path|chart tgz URL|repo/chart> (default: .)"
	@echo "                               Optional: HELM_CHART_VERSION=<chart version> (required with repo/chart)"
	@echo ""
	@echo "Terraform AKS targets:"
	@echo "  make tf-setup-aks          - terraform init + apply (VNet + AKS + StorageClass)"
	@echo "  make tf-plan-aks           - terraform plan (preview changes without applying)"
	@echo "  make tf-destroy-aks        - terraform destroy (tear down ALL Azure resources cleanly)"
	@echo "  make tf-output-aks         - Show terraform outputs (cluster name, kubeconfig cmd, etc.)"
	@echo ""
	@echo "GCP GKE Integration Testing targets:"
	@echo "  make gke-setup             - Provision GKE cluster via Terraform (tf-setup-gke)"
	@echo "  make gke-helm              - Install Helm chart with GKE values (standard-rwo, LoadBalancer)"
	@echo "  make gke-test              - Run full GKE integration test suite"
	@echo "  make gke-full              - Full GKE workflow (gke-setup + worker-config + helm + test)"
	@echo "  make gke-cleanup           - Uninstall Helm release from GKE (set DESTROY_CLUSTER=true to delete cluster)"
	@echo "                               Optional: HELM_CHART=<local path|chart tgz URL|repo/chart> (default: .)"
	@echo "                               Optional: HELM_CHART_VERSION=<chart version> (required with repo/chart)"
	@echo ""
	@echo "Terraform GKE targets:"
	@echo "  make tf-setup-gke          - terraform init + apply (GKE cluster + node pool)"
	@echo "  make tf-plan-gke           - terraform plan (preview changes without applying)"
	@echo "  make tf-destroy-gke        - terraform destroy (tear down ALL GCP resources cleanly)"
	@echo "  make tf-output-gke         - Show terraform outputs (cluster name, etc.)"
	@echo "================================"

# ================================
# Local Development Targets
# ================================

deps:
	@echo "Installing required tools..."
	@command -v helm >/dev/null 2>&1 || brew install helm
	@command -v kubeconform >/dev/null 2>&1 || brew install kubeconform
	@command -v yamllint >/dev/null 2>&1 || brew install yamllint
	@command -v trivy >/dev/null 2>&1 || brew install trivy
	@command -v kubescape >/dev/null 2>&1 || brew install kubescape
	@command -v prettier >/dev/null 2>&1 || npm install -g prettier
	@helm plugin list | grep -q unittest || helm plugin install https://github.com/helm-unittest/helm-unittest.git
	@echo "✅ All tools installed"

format:
	@echo "================================"
	@echo "Formatting YAML files with Prettier"
	@echo "================================"
	@if ! command -v prettier >/dev/null 2>&1; then \
		echo "❌ Prettier not found. Install with: npm install -g prettier"; \
		exit 1; \
	fi
	@echo "Formatting YAML files..."
	@prettier --write "**/*.{yaml,yml}" \
		--ignore-path .gitignore \
		--print-width 80 \
		--tab-width 2 \
		--prose-wrap preserve
	@echo "✅ All YAML files formatted"
	@echo ""

clean:
	@echo "Cleaning generated files..."
	@rm -f rendered.yaml yamllint-output.txt trivy-output.txt kubescape-output.json
	@echo "✅ Clean complete"

lint: deps
	@echo "================================"
	@echo "Running All Lints and Scans"
	@echo "================================"
	@echo ""
	@$(MAKE) lint-helm-k8s
	@echo ""
	@$(MAKE) trivy-scan
	@echo ""
	@$(MAKE) kubescape-scan
	@echo ""
	@echo "================================"
	@echo "✅ All lints and scans completed successfully!"
	@echo "================================"

# ================================
# Unit Testing Targets
# ================================

test: unit-test

unit-test:
	@echo "================================"
	@echo "Running Helm Unit Tests"
	@echo "================================"
	@if ! helm plugin list | grep -q unittest; then \
		echo "❌ helm-unittest plugin not found. Installing..."; \
		helm plugin install https://github.com/helm-unittest/helm-unittest.git; \
	fi
	@echo "Running unit tests..."
	@helm unittest . -f 'tests/unit/*_test.yaml'
	@echo "✅ Unit tests passed!"

# ================================
# CI/CD Setup Targets
# ================================

setup-helm-unittest:
	@echo "Installing helm-unittest plugin..."
	@helm plugin install https://github.com/helm-unittest/helm-unittest.git || true
	@helm plugin list | grep unittest
	@echo "✅ helm-unittest plugin installed"

setup-helm:
	@echo "Installing Helm..."
	@curl -fsSL -o /tmp/get-helm-3.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	@chmod +x /tmp/get-helm-3.sh
	@/tmp/get-helm-3.sh
	@helm version
	@echo "✅ Helm installed"

setup-kubeconform:
	@echo "Installing Kubeconform..."
	@curl -fsSL -o /tmp/kubeconform.tar.gz https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz
	@tar -xzf /tmp/kubeconform.tar.gz -C /tmp
	@sudo mv /tmp/kubeconform /usr/local/bin/
	@kubeconform -v
	@echo "✅ Kubeconform installed"

setup-trivy:
	@echo "Installing Trivy..."
	@sudo apt-get install -y wget apt-transport-https gnupg lsb-release
	@wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
	@echo "deb https://aquasecurity.github.io/trivy-repo/deb $$(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
	@sudo apt-get update
	@sudo apt-get install -y trivy
	@trivy --version
	@echo "✅ Trivy installed"

setup-kubescape:
	@echo "Installing Kubescape..."
	@curl -fsSL -o /tmp/kubescape-install.sh https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh
	@chmod +x /tmp/kubescape-install.sh
	@/tmp/kubescape-install.sh
	@export PATH=$$PATH:$$HOME/.kubescape/bin && \
		sudo cp $$HOME/.kubescape/bin/kubescape /usr/local/bin/ && \
		kubescape version
	@echo "✅ Kubescape installed"

# ================================
# CI/CD Lint & Scan Targets
# ================================

lint-helm-k8s:
	@echo "================================"
	@echo "Running Helm Lint"
	@echo "================================"
	helm lint .
	@echo "✅ Helm lint passed!"
	@echo ""
	@echo "================================"
	@echo "Rendering Helm Templates"
	@echo "================================"
	helm template boundary-worker . > rendered.yaml
	@echo "✅ Templates rendered successfully!"
	@echo "Rendered file size: $$(wc -l < rendered.yaml) lines"
	@echo ""
	@echo "================================"
	@echo "Running Kubernetes Validation"
	@echo "================================"
	kubeconform -strict rendered.yaml
	@echo "✅ Kubernetes validation passed!"

trivy-scan:
	@echo "================================"
	@echo "Running Security Scan with Trivy"
	@echo "================================"
	@trivy config rendered.yaml --exit-code 0 2>&1 | tee trivy-output.txt
	@CRITICAL_COUNT=$$(grep -E 'CRITICAL: [0-9]+' trivy-output.txt | sed -E 's/.*CRITICAL: ([0-9]+).*/\1/' | head -1); \
	HIGH_COUNT=$$(grep -E 'HIGH: [0-9]+' trivy-output.txt | sed -E 's/.*HIGH: ([0-9]+).*/\1/' | head -1); \
	MEDIUM_COUNT=$$(grep -E 'MEDIUM: [0-9]+' trivy-output.txt | sed -E 's/.*MEDIUM: ([0-9]+).*/\1/' | head -1); \
	LOW_COUNT=$$(grep -E 'LOW: [0-9]+' trivy-output.txt | sed -E 's/.*LOW: ([0-9]+).*/\1/' | head -1); \
	CRITICAL_COUNT=$${CRITICAL_COUNT:-0}; \
	HIGH_COUNT=$${HIGH_COUNT:-0}; \
	MEDIUM_COUNT=$${MEDIUM_COUNT:-0}; \
	LOW_COUNT=$${LOW_COUNT:-0}; \
	echo ""; \
	echo "Security Scan Results:"; \
	echo "  CRITICAL: $$CRITICAL_COUNT"; \
	echo "  HIGH: $$HIGH_COUNT"; \
	echo "  MEDIUM: $$MEDIUM_COUNT"; \
	echo "  LOW: $$LOW_COUNT"; \
	echo ""; \
	if [ $$CRITICAL_COUNT -gt 0 ] || [ $$HIGH_COUNT -gt 0 ]; then \
		echo "❌ Security scan FAILED: $$CRITICAL_COUNT CRITICAL, $$HIGH_COUNT HIGH issues"; \
		exit 1; \
	elif [ $$MEDIUM_COUNT -gt 0 ] || [ $$LOW_COUNT -gt 0 ]; then \
		echo "⚠️  Security scan completed with warnings: $$MEDIUM_COUNT MEDIUM, $$LOW_COUNT LOW issues"; \
	else \
		echo "✅ Security scan passed!"; \
	fi

kubescape-scan:
	@echo "================================"
	@echo "Running Security Scan with Kubescape"
	@echo "================================"
	@kubescape scan rendered.yaml \
		--format json \
		--output kubescape-output.json \
		--exceptions ./kubescape-exceptions.json \
		--verbose; KUBESCAPE_EXIT=$$?; \
	if [ $$KUBESCAPE_EXIT -ne 0 ] && [ ! -f kubescape-output.json ]; then \
		echo "❌ Kubescape failed to run (exit code: $$KUBESCAPE_EXIT)"; \
		exit $$KUBESCAPE_EXIT; \
	fi
	@echo ""
	@echo "================================"
	@echo "Kubescape Scan Results"
	@echo "================================"
	@if [ -f kubescape-output.json ]; then \
		if command -v jq >/dev/null 2>&1; then \
			COMPLIANCE_SCORE=$$(jq -r '.summaryDetails.complianceScore // 0' kubescape-output.json); \
			PASSED_RESOURCES=$$(jq -r '.summaryDetails.ResourceCounters.passedResources // 0' kubescape-output.json); \
			FAILED_CONTROLS=$$(jq '[.summaryDetails.controls[] | select(.failedResources != null and .failedResources > 0)] | length' kubescape-output.json); \
		else \
			echo "⚠️  jq not found, using grep fallback (less reliable)"; \
			COMPLIANCE_SCORE="N/A"; \
			PASSED_RESOURCES=$$(grep -o '"passedResources":[0-9]*' kubescape-output.json | head -1 | cut -d':' -f2 || echo "0"); \
			FAILED_CONTROLS=0; \
		fi; \
		echo "  Compliance Score: $$COMPLIANCE_SCORE%"; \
		echo "  Passed Resources: $$PASSED_RESOURCES"; \
		echo "  Failed Controls: $$FAILED_CONTROLS"; \
		echo ""; \
		if [ "$$FAILED_CONTROLS" -gt 0 ]; then \
			echo "❌ Kubescape scan FAILED: $$FAILED_CONTROLS control(s) have failed resources"; \
			exit 1; \
		else \
			echo "✅ Kubescape scan passed! All controls passed (compliance: $$COMPLIANCE_SCORE%)"; \
		fi; \
	else \
		echo "⚠️  Kubescape output file not found"; \
	fi


# ================================
# Acceptance Testing Targets
# ================================

acceptance-setup:
	@echo "================================"
	@echo "Setting up Acceptance Environment"
	@echo "================================"
	@echo ""
	@echo "Checking dependencies..."
	@# Check for kubectl
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "❌ kubectl is not installed"; \
		echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"; \
		exit 1; \
	fi
	@echo "✅ kubectl is installed ($$(kubectl version --client --short 2>/dev/null || kubectl version --client))"
	@# Check for kind
	@if ! command -v kind >/dev/null 2>&1; then \
		echo "❌ kind is not installed"; \
		echo "Installing kind..."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			brew install kind; \
		else \
			curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64; \
			chmod +x ./kind; \
			sudo mv ./kind /usr/local/bin/kind; \
		fi; \
	fi
	@echo "✅ kind is installed ($$(kind version))"
	@# Check for helm
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "❌ helm is not installed"; \
		echo "Installing helm..."; \
		curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	fi
	@echo "✅ helm is installed ($$(helm version --short 2>/dev/null || helm version))"
	@# Check for boundary CLI
	@if ! command -v boundary >/dev/null 2>&1; then \
		echo "⚠️  boundary CLI is not installed"; \
		echo "Installing boundary CLI..."; \
		ENV=$$(uname); \
		if [ "$$ENV" = "Darwin" ]; then \
			brew tap hashicorp/tap && brew install hashicorp/tap/boundary; \
		elif [ "$$ENV" = "Linux" ]; then \
			echo "Installing boundary CLI from HashiCorp APT repository..."; \
			wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
			echo "deb [arch=$$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list; \
			sudo apt update && sudo apt install -y boundary; \
		else \
			echo "❌ Failed to install Boundary"; \
			exit 1; \
		fi; \
	fi
	@echo "✅ boundary CLI is installed ($$(boundary version 2>/dev/null | head -n1 || echo 'version unknown'))"
	@echo ""
	@echo "Setting up KIND cluster..."
	@if kind get clusters | grep -q "^acceptance$$"; then \
		echo "⚠️  Acceptance cluster already exists"; \
	else \
		kind create cluster --config tests/acceptance/kind-acceptance-config.yaml; \
		echo "✅ Acceptance cluster created"; \
	fi
	@echo ""
	@echo "Verifying cluster..."
	@kubectl cluster-info --context kind-acceptance
	@echo "✅ Cluster is ready"
	@echo ""
	@echo "Installed tools:"
	@echo "  - kubectl: $$(kubectl version --client --short 2>/dev/null | head -n1 || echo 'installed')"
	@echo "  - kind: $$(kind version)"
	@echo "  - helm: $$(helm version --short 2>/dev/null | head -n1 || echo 'installed')"
	@echo "  - boundary: $$(boundary version 2>/dev/null | head -n1 || echo 'installed')"
	@echo ""
	@echo "Next steps:"
	@echo "  - Generate worker config: make worker-config"
	@echo "  - Install Helm chart and run Helm tests: make acceptance-helm"
	@echo "  - Run tests: make acceptance-test"
	@echo "  - Full workflow: make acceptance-full"
	@echo "  - Cleanup: make acceptance-cleanup"

worker-config:
	@echo "================================"
	@echo "Generating Worker Configuration"
	@echo "================================"
	@if [ -z "$$BOUNDARY_ADDR" ]; then \
		echo "❌ BOUNDARY_ADDR environment variable is not set"; \
		echo ""; \
		echo "Please set it to your Boundary controller address:"; \
		echo "  export BOUNDARY_ADDR=https://your-cluster.boundary.hashicorp.cloud"; \
		echo ""; \
		exit 1; \
	fi
	@if [ -z "$$BOUNDARY_LOGIN_NAME" ]; then \
		echo "❌ BOUNDARY_LOGIN_NAME environment variable is not set"; \
		echo ""; \
		echo "Please set it to your Boundary login name:"; \
		echo "  export BOUNDARY_LOGIN_NAME=admin"; \
		echo ""; \
		exit 1; \
	fi
	@if [ -z "$$BOUNDARY_PASSWORD" ]; then \
		echo "❌ BOUNDARY_PASSWORD environment variable is not set"; \
		echo ""; \
		echo "Please set it to your Boundary admin password:"; \
		echo "  export BOUNDARY_PASSWORD=your-password"; \
		echo ""; \
		exit 1; \
	fi
	@if [ -z "$$BOUNDARY_CLUSTER_ID" ]; then \
		echo "❌ BOUNDARY_CLUSTER_ID environment variable is not set"; \
		echo ""; \
		echo "Please set it to your Boundary cluster ID:"; \
		echo "  export BOUNDARY_CLUSTER_ID=your-cluster-id"; \
		echo ""; \
		exit 1; \
	fi

	@echo ""
	@echo "Authenticating with Boundary..."
	@echo "Boundary Address: $$BOUNDARY_ADDR"
	@echo "Login Name: $$BOUNDARY_LOGIN_NAME"
	@AUTH_OUT=$$(boundary authenticate password \
		-login-name $$BOUNDARY_LOGIN_NAME \
		-password env://BOUNDARY_PASSWORD \
		-keyring-type=none 2>&1); \
	STATUS=$$?; \
	if [ $$STATUS -ne 0 ]; then \
		echo "❌ Boundary authentication failed"; \
		printf '%s\n' "$$AUTH_OUT"; \
		exit $$STATUS; \
	fi; \
	AUTH_TOKEN=$$(printf '%s\n' "$$AUTH_OUT" | awk '/The token is:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$$/, "", $$0); print $$0; exit }'); \
	if [ -z "$$AUTH_TOKEN" ]; then \
		echo "❌ Failed to extract auth token from Boundary authenticate output"; \
		exit 1; \
	fi; \
	export AUTH_TOKEN; \
	echo "✅ Successfully authenticated with Boundary"; \
	echo ""; \
	echo "Creating controller-led worker..."; \
	TOKEN_OUT=$$(boundary workers create controller-led --token env://AUTH_TOKEN 2>&1); \
	STATUS=$$?; \
	if [ $$STATUS -ne 0 ]; then \
		echo "❌ Failed to create controller-led worker"; \
		printf '%s\n' "$$TOKEN_OUT"; \
		exit $$STATUS; \
	fi; \
	ACTIVATION_TOKEN=$$(printf '%s\n' "$$TOKEN_OUT" | awk -F': *' '/Controller-Generated Activation Token:/ { if ($$2 != "") { print $$2; exit } if (getline > 0) { gsub(/^[[:space:]]+|[[:space:]]+$$/, "", $$0); print $$0; exit } }'); \
	WORKER_ID=$$(printf '%s\n' "$$TOKEN_OUT" | awk -F': *' '/^  ID:/ { print $$2; exit }'); \
	if [ -z "$$ACTIVATION_TOKEN" ]; then \
		echo "❌ Failed to extract controller-generated activation token"; \
		exit 1; \
	fi; \
	export ACTIVATION_TOKEN; \
	if [ -n "$$WORKER_ID" ]; then \
		echo "✅ Created worker $$WORKER_ID"; \
	fi; \
	echo ""; \
	echo "Generating worker configuration from template..."; \
	sed -e "s|<activation-token>|$$ACTIVATION_TOKEN|g" -e "s|<cluster-id>|$$BOUNDARY_CLUSTER_ID|g" scripts/worker-template.hcl > worker.hcl; \
	echo "✅ Created worker config"

acceptance-helm:
	@echo "============================================"
	@echo "Installing Helm Chart in Acceptance Cluster"
	@echo "============================================"
	@echo ""
	@echo "Checking if Helm is installed..."
	@command -v helm >/dev/null 2>&1 || (echo "❌ Helm not found. Run 'make acceptance-setup' first"; exit 1)
	@if [ ! -f worker.hcl ]; then \
		echo "❌ worker.hcl not found. Run 'make worker-config' first"; \
		exit 1; \
	fi
	@echo "✅ Helm is available"
	@echo ""
	@echo "Installing boundary-worker chart with test values..."
	@helm upgrade --install boundary-worker . \
		--namespace boundary \
		--create-namespace \
		--kube-context kind-acceptance \
		--set worker.service.proxy.type=NodePort \
		--set worker.persistence.recording.storageClass=standard \
		--set worker.persistence.authStorage.storageClass=standard \
		--set-file worker.config=worker.hcl \
		--timeout 5m
	@echo "✅ Helm chart installed successfully"
	@echo ""
	@echo "Deployed resources:"
	@kubectl get all -n boundary --context kind-acceptance
	@echo ""
	@echo "Waiting for deployment to be ready..."
	@kubectl wait --for=condition=available --timeout=5m \
		deployment/boundary-worker-deployment \
		-n boundary \
		--context kind-acceptance
	@echo "✅ Deployment is ready"
	@echo ""
	@echo "Running Helm Tests..."
	@echo ""
	@echo "Cleaning up stale test pods..."
	@kubectl delete pods -n boundary --context kind-acceptance \
		-l app.kubernetes.io/component=test \
		--field-selector=status.phase=Failed \
		--ignore-not-found 2>/dev/null || true
	@echo "Running Helm test pods in boundary namespace..."
	@helm test boundary-worker \
		--namespace boundary \
		--kube-context kind-acceptance \
		--timeout 10m || true
	@echo ""
	@echo "Checking test results (controller-connection excluded)..."
	@FAILED=$$(kubectl get pods -n boundary --context kind-acceptance \
		-l app.kubernetes.io/component=test \
		--field-selector=status.phase=Failed \
		-o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
		| grep -v "controller-connection" || true); \
	if [ -n "$$FAILED" ]; then \
		echo "❌ Helm tests failed:"; \
		echo "$$FAILED"; \
		exit 1; \
	fi
	@echo "✅ Helm tests passed (controller-connection test excluded)"
	@echo ""
	@echo "Note: Test pod logs are not displayed as pods are deleted after completion."
	@echo "To view logs during test execution, run: kubectl logs -n boundary -l app.kubernetes.io/component=test --follow"

acceptance-test:
	@bash tests/acceptance/cluster-smoke-test.sh
	@bash tests/acceptance/tcp-target-conn-test.sh
	@bash tests/acceptance/cleanup-worker.sh
	@bash tests/acceptance/kind-version-matrix-test.sh
	@echo "✅ All acceptance tests passed!"
	@echo ""


acceptance-full:
	@echo "================================"
	@echo "Running Full Acceptance Workflow"
	@echo "================================"
	@echo ""
	@if kind get clusters | grep -q "^acceptance$$"; then \
		echo "⚠️  KIND cluster 'acceptance' already exists — skipping acceptance-setup"; \
	else \
		$(MAKE) acceptance-setup; \
	fi
	@$(MAKE) worker-config
	@$(MAKE) acceptance-helm
	@$(MAKE) acceptance-test
	@echo ""
	@echo "To cleanup, run: make acceptance-cleanup"
	@echo ""

# ================================
# KIND Version Matrix Testing
# ================================

kind-matrix-test:
	@echo "================================"
	@echo "KIND Version Matrix Test"
	@echo "Versions: resolved dynamically from GitHub Releases"
	@echo "================================"
	@chmod +x tests/acceptance/kind-version-matrix-test.sh
	@bash tests/acceptance/kind-version-matrix-test.sh

kind-matrix-cleanup:
	@echo "================================"
	@echo "KIND Matrix Cleanup"
	@echo "================================"
	@find "$${TMPDIR:-/tmp}" -maxdepth 1 -name 'kind-v[0-9]*' 2>/dev/null | while read -r BIN; do \
		if [ -x "$$BIN" ] && "$$BIN" get clusters 2>/dev/null | grep -q "^acceptance$$"; then \
			echo "Deleting cluster using $$(basename $$BIN) binary..."; \
			"$$BIN" delete cluster --name acceptance; \
		fi; \
		rm -f "$$BIN"; \
		echo "✅ Removed cached $$(basename $$BIN) binary"; \
	done
	@rm -f worker.hcl
	@rm -f /tmp/boundary-worker-id.txt
	@echo "✅ KIND matrix cleanup complete"

acceptance-cleanup:
	@echo "================================"
	@echo "Cleaning up Acceptance Cluster"
	@echo "================================"
	@echo "Cleaning up worker from Boundary cluster..."
	@bash tests/acceptance/cleanup-worker.sh || true
	@echo ""
	@if kind get clusters | grep -q "^acceptance$$"; then \
		echo "Deleting KIND cluster 'acceptance'..."; \
		kind delete cluster --name acceptance; \
		echo "✅ Acceptance cluster deleted"; \
	else \
		echo "⚠️  Acceptance cluster does not exist"; \
	fi
	@find "$${TMPDIR:-/tmp}" -maxdepth 1 -name 'kind-v[0-9]*' 2>/dev/null | while read -r BIN; do \
		rm -f "$$BIN"; \
		echo "✅ Removed cached $$(basename $$BIN) binary"; \
	done
	@rm -f worker.hcl
	@echo "✅ Removed worker.hcl"
	@rm -f /tmp/boundary-worker-id.txt
	@echo "✅ Removed worker ID file"

# ================================
# AWS EKS Acceptance Testing Targets
# ================================

eks-setup:
	@$(MAKE) tf-setup

eks-helm:
	@echo "Installing Helm Chart on EKS..."
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@[ -f worker.hcl ] || { echo "❌ worker.hcl not found. Run 'make worker-config' first"; exit 1; }
	@AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
		{ echo "❌ AWS credentials not configured"; exit 1; }; \
	EKS_CONTEXT="arn:aws:eks:$${AWS_REGION}:$${AWS_ACCOUNT_ID}:cluster/$${EKS_CLUSTER_NAME}"; \
	HELM_CHART_REF="$(HELM_CHART)"; \
	CHART_VERSION_ARG=""; \
	case "$${HELM_CHART_REF}" in \
		.|./*|/*|*://*|*.tgz) ;; \
		*/*) \
			if [ -z "$(HELM_CHART_VERSION)" ]; then \
				echo "❌ HELM_CHART_VERSION is required when HELM_CHART is a repo/chart reference (got '$${HELM_CHART_REF}')."; \
				exit 1; \
			fi; \
			CHART_VERSION_ARG="--version $(HELM_CHART_VERSION)" ;; \
	esac; \
	echo "Updating kubeconfig for cluster $${EKS_CLUSTER_NAME}..."; \
	aws eks update-kubeconfig --name "$${EKS_CLUSTER_NAME}" --region "$${AWS_REGION}"; \
	echo "Installing/upgrading boundary-worker chart from '$${HELM_CHART_REF}' with EKS values..."; \
	helm upgrade --install boundary-worker "$${HELM_CHART_REF}" \
		$${CHART_VERSION_ARG} \
		--namespace boundary \
		--create-namespace \
		--kube-context "$${EKS_CONTEXT}" \
		--set worker.service.proxy.type=LoadBalancer \
		--set worker.persistence.recording.storageClass=gp3 \
		--set worker.persistence.authStorage.storageClass=gp3 \
		--set-file worker.config=worker.hcl \
		--timeout 10m \
		--wait \
		--atomic; \
	echo ""; \
	echo "Deployed resources:"; \
	kubectl get all -n boundary --context "$${EKS_CONTEXT}"
	@echo ""
	@echo "✅ Helm chart installed/upgraded on EKS"
	@echo ""

eks-test:
	@echo "Running EKS Acceptance Tests..."
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set. Check your .env or export it."; \
			exit 1; \
		fi; \
	done
	@bash tests/integration/eks-integration-test.sh
	@echo ""

eks-full:
	@echo "================================"
	@echo "Full EKS Integration Workflow"
	@echo "================================"
	@echo ""
	@echo "Using chart source: $(HELM_CHART)"
	@echo "Using chart version: $(if $(HELM_CHART_VERSION),$(HELM_CHART_VERSION),<auto/local>)"
	@$(MAKE) tf-setup
	@$(MAKE) worker-config
	@$(MAKE) eks-helm HELM_CHART="$(HELM_CHART)" HELM_CHART_VERSION="$(HELM_CHART_VERSION)"
	@$(MAKE) eks-test
	@echo ""
	@echo "✅ End-to-end EKS workflow has been completed successfully"
	@echo ""
	@echo "To cleanup: make eks-cleanup or DESTROY_CLUSTER=true make eks-cleanup (to also destroy the cluster)"

eks-cleanup:
	@echo "================================"
	@echo "Cleaning Up EKS Resources"
	@echo "================================"
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
		{ echo "❌ AWS credentials not configured"; exit 1; }; \
	EKS_CONTEXT="arn:aws:eks:$${AWS_REGION}:$${AWS_ACCOUNT_ID}:cluster/$${EKS_CLUSTER_NAME}"; \
	aws eks update-kubeconfig --name "$${EKS_CLUSTER_NAME}" --region "$${AWS_REGION}" 2>/dev/null || true; \
	if helm status boundary-worker -n boundary --kube-context "$${EKS_CONTEXT}" >/dev/null 2>&1; then \
		echo "Uninstalling Helm release boundary-worker..."; \
		helm uninstall boundary-worker --namespace boundary --kube-context "$${EKS_CONTEXT}" --wait --timeout 5m; \
		echo "✅ Helm release uninstalled"; \
	else \
		echo "⚠️  Helm release not found"; \
	fi; \
	kubectl delete namespace boundary --context "$${EKS_CONTEXT}" --ignore-not-found 2>/dev/null || true
	@rm -f worker.hcl
	@echo "✅ Removed worker.hcl"
	@if [ "$${DESTROY_CLUSTER:-false}" = "true" ]; then \
		echo ""; \
		echo "Destroying Terraform EKS stack (DESTROY_CLUSTER=true)..."; \
		$(MAKE) tf-destroy; \
	else \
		echo ""; \
		echo "ℹ  EKS cluster retained. To destroy: DESTROY_CLUSTER=true make eks-cleanup"; \
	fi

# ================================
# Terraform EKS Targets (Recommended)
# ================================

tf-plan:
	@echo "================================"
	@echo "Terraform Plan (EKS)"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@cd tests/integration/terraform/aws && \
		terraform init -upgrade && \
		terraform plan \
			-var="aws_region=$${AWS_REGION}" \
			-var="cluster_name=$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_type=$${TF_NODE_TYPE:-t3.medium}" \
			-var="node_desired=$${TF_NODE_DESIRED:-2}" \
			-var="node_min=$${TF_NODE_MIN:-1}" \
			-var="node_max=$${TF_NODE_MAX:-3}" \
			-var="lbc_chart_version=$${TF_LBC_CHART_VERSION:-1.8.1}" \
			-var="allowed_public_access_cidrs=[$${TF_ALLOWED_PUBLIC_ACCESS_CIDRS:-\"0.0.0.0/0\"}]"

tf-setup:
	@echo "================================"
	@echo "Provisioning EKS with Terraform"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@cd tests/integration/terraform/aws && \
		terraform init -upgrade && \
		terraform apply -auto-approve \
			-var="aws_region=$${AWS_REGION}" \
			-var="cluster_name=$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_type=$${TF_NODE_TYPE:-t3.medium}" \
			-var="node_desired=$${TF_NODE_DESIRED:-2}" \
			-var="node_min=$${TF_NODE_MIN:-1}" \
			-var="node_max=$${TF_NODE_MAX:-3}" \
			-var="lbc_chart_version=$${TF_LBC_CHART_VERSION:-1.8.1}" \
			-var="allowed_public_access_cidrs=[$${TF_ALLOWED_PUBLIC_ACCESS_CIDRS:-\"0.0.0.0/0\"}]" \
			-target=module.vpc \
			-target=module.eks \
			-target=module.ebs_csi_irsa_role \
			-target=module.lbc_irsa_role
	@echo "   Importing existing gp3 StorageClass into Terraform state (if present)..."
	@cd tests/integration/terraform/aws && \
		terraform import \
			-var="aws_region=$${AWS_REGION}" \
			-var="cluster_name=$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}" \
			kubernetes_storage_class_v1.gp3 gp3 2>/dev/null || true
	@echo "   Removing stale outputs from Terraform state (if any)..."
	@cd tests/integration/terraform/aws && \
		terraform state rm output.next_steps 2>/dev/null || true
	@cd tests/integration/terraform/aws && \
		terraform apply -auto-approve \
			-var="aws_region=$${AWS_REGION}" \
			-var="cluster_name=$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_type=$${TF_NODE_TYPE:-t3.medium}" \
			-var="node_desired=$${TF_NODE_DESIRED:-2}" \
			-var="node_min=$${TF_NODE_MIN:-1}" \
			-var="node_max=$${TF_NODE_MAX:-3}" \
			-var="lbc_chart_version=$${TF_LBC_CHART_VERSION:-1.8.1}" \
			-var="allowed_public_access_cidrs=[$${TF_ALLOWED_PUBLIC_ACCESS_CIDRS:-\"0.0.0.0/0\"}]"
	@echo ""
	@KUBECONFIG_CMD=$$(cd tests/integration/terraform/aws && terraform output -raw kubeconfig_command 2>/dev/null); \
	if [ -n "$$KUBECONFIG_CMD" ]; then \
		echo "Updating kubeconfig..."; \
		eval "$$KUBECONFIG_CMD"; \
	fi
	@echo ""
	@echo "✅ EKS cluster and all prerequisites are ready"
	@echo ""

tf-output:
	@echo "================================"
	@echo "Terraform Outputs"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@cd tests/integration/terraform/aws && terraform output

# ================================
# Azure AKS Integration Testing Targets
# ================================

aks-setup:
	@$(MAKE) tf-setup-aks

aks-helm:
	@echo "Installing Helm Chart on AKS..."
	@echo ""
	@for v in AZURE_RESOURCE_GROUP AKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@[ -f worker.hcl ] || { echo "❌ worker.hcl not found. Run 'make worker-config' first"; exit 1; }
	@echo "Updating kubeconfig for cluster $${AKS_CLUSTER_NAME}..."; \
	az aks get-credentials \
		--resource-group "$${AZURE_RESOURCE_GROUP}" \
		--name "$${AKS_CLUSTER_NAME}" \
		--overwrite-existing; \
	AKS_CONTEXT="$${AKS_CLUSTER_NAME}"; \
	HELM_CHART_REF="$(HELM_CHART)"; \
	CHART_VERSION_ARG=""; \
	case "$${HELM_CHART_REF}" in \
		.|./*|/*|*://*|*.tgz) ;; \
		*/*) \
			if [ -z "$(HELM_CHART_VERSION)" ]; then \
				echo "❌ HELM_CHART_VERSION is required when HELM_CHART is a repo/chart reference (got '$${HELM_CHART_REF}')."; \
				exit 1; \
			fi; \
			CHART_VERSION_ARG="--version $(HELM_CHART_VERSION)" ;; \
	esac; \
	STORAGE_CLASS="$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}"; \
	echo "Installing/upgrading boundary-worker chart from '$${HELM_CHART_REF}' with AKS values..."; \
	helm upgrade --install boundary-worker "$${HELM_CHART_REF}" \
		$${CHART_VERSION_ARG} \
		--namespace boundary \
		--create-namespace \
		--kube-context "$${AKS_CONTEXT}" \
		--set worker.service.proxy.type=LoadBalancer \
		--set worker.persistence.recording.storageClass=$${STORAGE_CLASS} \
		--set worker.persistence.authStorage.storageClass=$${STORAGE_CLASS} \
		--set-file worker.config=worker.hcl \
		--timeout 10m \
		--wait \
		--atomic; \
	echo ""; \
	echo "Deployed resources:"; \
	kubectl get all -n boundary --context "$${AKS_CONTEXT}"
	@echo ""
	@echo "✅ Helm chart installed/upgraded on AKS"
	@echo ""

aks-test:
	@echo "Running AKS Integration Tests..."
	@echo ""
	@for v in AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_LOCATION AZURE_RESOURCE_GROUP AKS_CLUSTER_NAME BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set. Check your .env or export it."; \
			exit 1; \
		fi; \
	done
	@echo "Setting Azure subscription $${AZURE_SUBSCRIPTION_ID}..."; \
	CURRENT_TENANT=$$(az account show --query tenantId -o tsv 2>/dev/null || true); \
	if [ "$$CURRENT_TENANT" != "$${AZURE_TENANT_ID}" ]; then \
		echo "Not logged in to tenant $${AZURE_TENANT_ID}, running az login..."; \
		az login --tenant "$${AZURE_TENANT_ID}"; \
	fi; \
	az account set --subscription "$${AZURE_SUBSCRIPTION_ID}"
	@bash tests/integration/aks-integration-test.sh
	@echo ""

aks-full:
	@echo "================================"
	@echo "Full AKS Integration Workflow"
	@echo "================================"
	@echo ""
	@echo "Using chart source: $(HELM_CHART)"
	@echo "Using chart version: $(if $(HELM_CHART_VERSION),$(HELM_CHART_VERSION),<auto/local>)"
	@$(MAKE) tf-setup-aks
	@$(MAKE) worker-config
	@$(MAKE) aks-helm HELM_CHART="$(HELM_CHART)" HELM_CHART_VERSION="$(HELM_CHART_VERSION)"
	@$(MAKE) aks-test
	@echo ""
	@echo "✅ End-to-end AKS workflow has been completed successfully"
	@echo ""
	@echo "To cleanup: make aks-cleanup or DESTROY_CLUSTER=true make aks-cleanup (to also destroy the cluster)"

aks-cleanup:
	@echo "================================"
	@echo "Cleaning Up AKS Resources"
	@echo "================================"
	@echo ""
	@for v in AZURE_RESOURCE_GROUP AKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@az aks get-credentials \
		--resource-group "$${AZURE_RESOURCE_GROUP}" \
		--name "$${AKS_CLUSTER_NAME}" \
		--overwrite-existing 2>/dev/null || true; \
	AKS_CONTEXT="$${AKS_CLUSTER_NAME}"; \
	if helm status boundary-worker -n boundary --kube-context "$${AKS_CONTEXT}" >/dev/null 2>&1; then \
		echo "Uninstalling Helm release boundary-worker..."; \
		helm uninstall boundary-worker --namespace boundary --kube-context "$${AKS_CONTEXT}" --wait --timeout 5m; \
		echo "✅ Helm release uninstalled"; \
	else \
		echo "⚠️  Helm release not found"; \
	fi; \
	kubectl delete namespace boundary --context "$${AKS_CONTEXT}" --ignore-not-found 2>/dev/null || true
	@rm -f worker.hcl
	@echo "✅ Removed worker.hcl"
	@if [ "$${DESTROY_CLUSTER:-false}" = "true" ]; then \
		echo ""; \
		echo "Destroying Terraform AKS stack (DESTROY_CLUSTER=true)..."; \
		$(MAKE) tf-destroy-aks; \
	else \
		echo ""; \
		echo "ℹ  AKS cluster retained. To destroy: DESTROY_CLUSTER=true make aks-cleanup"; \
	fi

# ================================
# Terraform AKS Targets
# ================================

tf-plan-aks:
	@echo "================================"
	@echo "Terraform Plan (AKS)"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@cd tests/integration/terraform/azure && \
		terraform init -upgrade && \
		terraform plan \
			-var="azure_subscription_id=$${AZURE_SUBSCRIPTION_ID:-}" \
			-var="azure_location=$${AZURE_LOCATION:-eastus}" \
			-var="resource_group_name=$${AZURE_RESOURCE_GROUP:-boundary-worker-rg}" \
			-var="cluster_name=$${AKS_CLUSTER_NAME:-boundary-aks-cluster}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_vm_size=$${TF_NODE_VM_SIZE:-Standard_D2s_v3}" \
			-var="node_count=$${TF_NODE_COUNT:-2}" \
			-var="node_min_count=$${TF_NODE_MIN:-1}" \
			-var="node_max_count=$${TF_NODE_MAX:-3}" \
			-var="storage_class_name=$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}"

tf-setup-aks:
	@echo "================================"
	@echo "Provisioning AKS with Terraform"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@command -v az >/dev/null 2>&1 || { echo "❌ Azure CLI not found. Install: brew install azure-cli"; exit 1; }
	@echo "Ensuring required Azure resource providers are registered..."
	@SUB_FLAG=""; \
	if [ -n "$${AZURE_SUBSCRIPTION_ID:-}" ]; then \
		SUB_FLAG="--subscription $${AZURE_SUBSCRIPTION_ID}"; \
	fi; \
	for ns in Microsoft.ContainerService Microsoft.Network Microsoft.Compute Microsoft.Storage; do \
		STATE=$$(az provider show --namespace "$$ns" $$SUB_FLAG --query "registrationState" -o tsv 2>/dev/null || echo "Unknown"); \
		if [ "$$STATE" != "Registered" ]; then \
			echo "  Registering $$ns (current state: $$STATE)..."; \
			az provider register --namespace "$$ns" $$SUB_FLAG --wait; \
			echo "  ✅ $$ns registered"; \
		else \
			echo "  ✅ $$ns already registered"; \
		fi; \
	done
	@cd tests/integration/terraform/azure && \
		terraform init -upgrade && \
		terraform apply -auto-approve \
			-target=azurerm_resource_group.aks \
			-target=azurerm_virtual_network.aks \
			-target=azurerm_subnet.aks_nodes \
			-target=azurerm_kubernetes_cluster.aks \
			-var="azure_subscription_id=$${AZURE_SUBSCRIPTION_ID:-}" \
			-var="azure_location=$${AZURE_LOCATION:-eastus}" \
			-var="resource_group_name=$${AZURE_RESOURCE_GROUP:-boundary-worker-rg}" \
			-var="cluster_name=$${AKS_CLUSTER_NAME:-boundary-aks-cluster}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_vm_size=$${TF_NODE_VM_SIZE:-Standard_D2s_v3}" \
			-var="node_count=$${TF_NODE_COUNT:-2}" \
			-var="node_min_count=$${TF_NODE_MIN:-1}" \
			-var="node_max_count=$${TF_NODE_MAX:-3}" \
			-var="storage_class_name=$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}" && \
		terraform import kubernetes_storage_class_v1.managed_csi_premium "$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}" 2>/dev/null || true && \
		terraform apply -auto-approve \
			-var="azure_subscription_id=$${AZURE_SUBSCRIPTION_ID:-}" \
			-var="azure_location=$${AZURE_LOCATION:-eastus}" \
			-var="resource_group_name=$${AZURE_RESOURCE_GROUP:-boundary-worker-rg}" \
			-var="cluster_name=$${AKS_CLUSTER_NAME:-boundary-aks-cluster}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_vm_size=$${TF_NODE_VM_SIZE:-Standard_D2s_v3}" \
			-var="node_count=$${TF_NODE_COUNT:-2}" \
			-var="node_min_count=$${TF_NODE_MIN:-1}" \
			-var="node_max_count=$${TF_NODE_MAX:-3}" \
			-var="storage_class_name=$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}"
	@echo ""
	@KUBECONFIG_CMD=$$(cd tests/integration/terraform/azure && terraform output -raw kubeconfig_command 2>/dev/null); \
	if [ -n "$$KUBECONFIG_CMD" ]; then \
		echo "Updating kubeconfig..."; \
		eval "$$KUBECONFIG_CMD"; \
	fi
	@echo ""
	@echo "✅ AKS cluster and all prerequisites are ready"
	@echo ""

tf-destroy-aks:
	@echo "================================"
	@echo "Destroying AKS Terraform Stack"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@cd tests/integration/terraform/azure && \
		terraform init -upgrade && \
		terraform destroy -auto-approve \
			-var="azure_subscription_id=$${AZURE_SUBSCRIPTION_ID:-}" \
			-var="azure_location=$${AZURE_LOCATION:-eastus}" \
			-var="resource_group_name=$${AZURE_RESOURCE_GROUP:-boundary-worker-rg}" \
			-var="cluster_name=$${AKS_CLUSTER_NAME:-boundary-aks-cluster}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_vm_size=$${TF_NODE_VM_SIZE:-Standard_D2s_v3}" \
			-var="node_count=$${TF_NODE_COUNT:-2}" \
			-var="node_min_count=$${TF_NODE_MIN:-1}" \
			-var="node_max_count=$${TF_NODE_MAX:-3}" \
			-var="storage_class_name=$${TF_STORAGE_CLASS_NAME:-managed-csi-premium}"
	@echo ""
	@echo "✅ AKS cluster and all Azure resources destroyed"
	@echo ""

tf-output-aks:
	@echo "================================"
	@echo "Terraform Outputs (AKS)"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@cd tests/integration/terraform/azure && terraform output

# ================================
# GCP GKE Integration Testing Targets
# ================================

gke-setup:
	@$(MAKE) tf-setup-gke

gke-helm:
	@echo "Installing Helm Chart on GKE..."
	@echo ""
	@for v in GCP_PROJECT_ID GCP_REGION GKE_ZONE GKE_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@[ -f worker.hcl ] || { echo "❌ worker.hcl not found. Run 'make worker-config' first"; exit 1; }
	@echo "Updating kubeconfig for cluster $${GKE_CLUSTER_NAME}..."; \
	gcloud container clusters get-credentials "$${GKE_CLUSTER_NAME}" \
		--zone "$${GKE_ZONE}" \
		--project "$${GCP_PROJECT_ID}"; \
	GKE_CONTEXT="gke_$${GCP_PROJECT_ID}_$${GKE_ZONE}_$${GKE_CLUSTER_NAME}"; \
	HELM_CHART_REF="$(HELM_CHART)"; \
	CHART_VERSION_ARG=""; \
	case "$${HELM_CHART_REF}" in \
		.|./*|/*|*://*|*.tgz) ;; \
		*/*) \
			if [ -z "$(HELM_CHART_VERSION)" ]; then \
				echo "❌ HELM_CHART_VERSION is required when HELM_CHART is a repo/chart reference (got '$${HELM_CHART_REF}')."; \
				exit 1; \
			fi; \
			CHART_VERSION_ARG="--version $(HELM_CHART_VERSION)" ;; \
	esac; \
	STORAGE_CLASS="$${TF_STORAGE_CLASS_NAME:-standard-rwo}"; \
	echo "Installing/upgrading boundary-worker chart from '$${HELM_CHART_REF}' with GKE values..."; \
	helm upgrade --install boundary-worker "$${HELM_CHART_REF}" \
		$${CHART_VERSION_ARG} \
		--namespace boundary \
		--create-namespace \
		--kube-context "$${GKE_CONTEXT}" \
		--set worker.service.proxy.type=LoadBalancer \
		--set worker.persistence.recording.storageClass=$${STORAGE_CLASS} \
		--set worker.persistence.authStorage.storageClass=$${STORAGE_CLASS} \
		--set-file worker.config=worker.hcl \
		--timeout 10m \
		--wait \
		--atomic; \
	echo ""; \
	echo "Deployed resources:"; \
	kubectl get all -n boundary --context "$${GKE_CONTEXT}"
	@echo ""
	@echo "✅ Helm chart installed/upgraded on GKE"
	@echo ""

gke-test:
	@echo "Running GKE Integration Tests..."
	@echo ""
	@for v in GCP_PROJECT_ID GCP_REGION GKE_ZONE GKE_CLUSTER_NAME BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set. Check your .env or export it."; \
			exit 1; \
		fi; \
	done
	@bash tests/integration/gke-integration-test.sh
	@echo ""

gke-full:
	@echo "================================"
	@echo "Full GKE Integration Workflow"
	@echo "================================"
	@echo ""
	@echo "Using chart source: $(HELM_CHART)"
	@echo "Using chart version: $(if $(HELM_CHART_VERSION),$(HELM_CHART_VERSION),<auto/local>)"
	@$(MAKE) tf-setup-gke
	@$(MAKE) worker-config
	@$(MAKE) gke-helm HELM_CHART="$(HELM_CHART)" HELM_CHART_VERSION="$(HELM_CHART_VERSION)"
	@$(MAKE) gke-test
	@echo ""
	@echo "✅ End-to-end GKE workflow has been completed successfully"
	@echo ""
	@echo "To cleanup: make gke-cleanup or DESTROY_CLUSTER=true make gke-cleanup (to also destroy the cluster)"

gke-cleanup:
	@echo "================================"
	@echo "Cleaning Up GKE Resources"
	@echo "================================"
	@echo ""
	@for v in GCP_PROJECT_ID GCP_REGION GKE_ZONE GKE_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@gcloud container clusters get-credentials "$${GKE_CLUSTER_NAME}" \
		--zone "$${GKE_ZONE}" \
		--project "$${GCP_PROJECT_ID}" >/dev/null 2>&1 || true; \
	GKE_CONTEXT="gke_$${GCP_PROJECT_ID}_$${GKE_ZONE}_$${GKE_CLUSTER_NAME}"; \
	if helm status boundary-worker -n boundary --kube-context "$${GKE_CONTEXT}" >/dev/null 2>&1; then \
		echo "Uninstalling Helm release boundary-worker..."; \
		helm uninstall boundary-worker --namespace boundary --kube-context "$${GKE_CONTEXT}" --wait --timeout 5m; \
		echo "✅ Helm release uninstalled"; \
	else \
		echo "⚠️  Helm release not found"; \
	fi; \
	kubectl delete namespace boundary --context "$${GKE_CONTEXT}" --ignore-not-found 2>/dev/null || true
	@rm -f worker.hcl
	@echo "✅ Removed worker.hcl"
	@if [ "$${DESTROY_CLUSTER:-false}" = "true" ]; then \
		echo ""; \
		echo "Destroying Terraform GKE stack (DESTROY_CLUSTER=true)..."; \
		$(MAKE) tf-destroy-gke; \
	else \
		echo ""; \
		echo "ℹ  GKE cluster retained. To destroy: DESTROY_CLUSTER=true make gke-cleanup"; \
	fi

# ================================
# Terraform GKE Targets
# ================================

tf-plan-gke:
	@echo "================================"
	@echo "Terraform Plan (GKE)"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud not found. Install Google Cloud SDK first."; exit 1; }
	@if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then \
		echo "❌ Google ADC is missing or expired (reauth required)."; \
		echo "   Run: gcloud auth application-default login"; \
		echo "   If your org enforces reauth, also run: gcloud auth login"; \
		exit 1; \
	fi
	@cd tests/integration/terraform/gcp && \
		terraform init -upgrade && \
		terraform plan \
			-var="project_id=$${GCP_PROJECT_ID:-}" \
			-var="region=$${GCP_REGION:-us-central1}" \
			-var="zone=$${GKE_ZONE:-us-central1-a}" \
			-var="cluster_name=$${GKE_CLUSTER_NAME:-boundary-gke-cluster}" \
			-var="node_count=$${TF_NODE_COUNT:-2}"

tf-setup-gke:
	@echo "================================"
	@echo "Provisioning GKE with Terraform"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found. Install: brew install terraform"; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud not found. Install Google Cloud SDK first."; exit 1; }
	@if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then \
		echo "❌ Google ADC is missing or expired (reauth required)."; \
		echo "   Run: gcloud auth application-default login"; \
		echo "   If your org enforces reauth, also run: gcloud auth login"; \
		exit 1; \
	fi
	@cd tests/integration/terraform/gcp && \
		terraform init -upgrade && \
		terraform apply -auto-approve \
			-var="project_id=$${GCP_PROJECT_ID:-}" \
			-var="region=$${GCP_REGION:-us-central1}" \
			-var="zone=$${GKE_ZONE:-us-central1-a}" \
			-var="cluster_name=$${GKE_CLUSTER_NAME:-boundary-gke-cluster}" \
			-var="node_count=$${TF_NODE_COUNT:-2}"
	@echo ""
	@echo "Updating kubeconfig..."
	@gcloud container clusters get-credentials "$${GKE_CLUSTER_NAME:-boundary-gke-cluster}" \
		--zone "$${GKE_ZONE:-us-central1-a}" \
		--region "$${GCP_REGION:-us-central1}" \
		--project "$${GCP_PROJECT_ID:-}"
	@echo ""
	@echo "✅ GKE cluster and all prerequisites are ready"
	@echo ""

tf-destroy-gke:
	@echo "================================"
	@echo "Destroying GKE Terraform Stack"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo "❌ gcloud not found. Install Google Cloud SDK first."; exit 1; }
	@if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then \
		echo "❌ Google ADC is missing or expired (reauth required)."; \
		echo "   Run: gcloud auth application-default login"; \
		echo "   If your org enforces reauth, also run: gcloud auth login"; \
		exit 1; \
	fi
	@cd tests/integration/terraform/gcp && \
		terraform init -upgrade && \
		terraform destroy -auto-approve \
			-var="project_id=$${GCP_PROJECT_ID:-}" \
			-var="region=$${GCP_REGION:-us-central1}" \
			-var="zone=$${GKE_ZONE:-us-central1-a}" \
			-var="cluster_name=$${GKE_CLUSTER_NAME:-boundary-gke-cluster}" \
			-var="node_count=$${TF_NODE_COUNT:-2}"
	@echo ""
	@echo "✅ GKE cluster and all GCP resources destroyed"
	@echo ""

tf-output-gke:
	@echo "================================"
	@echo "Terraform Outputs (GKE)"
	@echo "================================"
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@cd tests/integration/terraform/gcp && terraform output

tf-destroy:
	@echo "================================"
	@echo "Destroying EKS Terraform Stack"
	@echo "================================"
	@echo "⚠️  This will delete the EKS cluster, VPC, node groups, IAM roles, and all associated resources."
	@echo ""
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@STATE_FILE="tests/integration/terraform/aws/terraform.tfstate"; \
	if [ ! -f "$$STATE_FILE" ]; then \
		echo "❌ Terraform state file not found: $$STATE_FILE"; \
		echo "   The cluster may have been provisioned outside this workspace, or state was lost."; \
		echo "   Use 'make eks-cleanup' with manual AWS CLI cleanup if the cluster still exists."; \
		exit 1; \
	fi; \
	RESOURCE_COUNT=$$(python3 -c "import json,sys; d=json.load(open('$$STATE_FILE')); print(len(d.get('resources', [])))" 2>/dev/null || echo 0); \
	if [ "$$RESOURCE_COUNT" = "0" ]; then \
		echo "⚠️  Terraform state is empty (0 resources tracked)."; \
		echo "   terraform destroy would exit 0 without deleting anything."; \
		echo ""; \
		CLUSTER_NAME="$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}"; \
		CLUSTER_STATUS=$$(aws eks describe-cluster --name "$$CLUSTER_NAME" --region "$${AWS_REGION}" \
			--query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND"); \
		if [ "$$CLUSTER_STATUS" = "NOT_FOUND" ] || [ "$$CLUSTER_STATUS" = "None" ]; then \
			echo "✅ Cluster '$$CLUSTER_NAME' not found in AWS — already deleted."; \
			exit 0; \
		else \
			echo "⚠️  Terraform state is out of sync — falling back to direct AWS CLI cleanup."; \
			echo ""; \
			VPC_ID=$$(aws eks describe-cluster --name "$$CLUSTER_NAME" --region "$${AWS_REGION}" \
				--query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo ""); \
			echo "--- Deleting node groups for cluster '$$CLUSTER_NAME' ---"; \
			for ng in $$(aws eks list-nodegroups --cluster-name "$$CLUSTER_NAME" --region "$${AWS_REGION}" \
				--query 'nodegroups[*]' --output text | tr '\t' '\n'); do \
				echo "  Deleting node group: $$ng"; \
				aws eks delete-nodegroup --cluster-name "$$CLUSTER_NAME" --nodegroup-name "$$ng" \
					--region "$${AWS_REGION}" --output json > /dev/null; \
				echo "  Waiting for node group '$$ng' to be deleted..."; \
				aws eks wait nodegroup-deleted --cluster-name "$$CLUSTER_NAME" \
					--nodegroup-name "$$ng" --region "$${AWS_REGION}"; \
				echo "  ✅ Node group '$$ng' deleted"; \
			done; \
			echo "--- Deleting NAT Gateways in VPC '$$VPC_ID' ---"; \
			for nat in $$(aws ec2 describe-nat-gateways --region "$${AWS_REGION}" \
				--filter "Name=vpc-id,Values=$$VPC_ID" "Name=state,Values=available,pending" \
				--query 'NatGateways[*].NatGatewayId' --output text | tr '\t' '\n'); do \
				EIP=$$(aws ec2 describe-nat-gateways --region "$${AWS_REGION}" \
					--nat-gateway-ids "$$nat" \
					--query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null); \
				echo "  Deleting NAT Gateway: $$nat"; \
				aws ec2 delete-nat-gateway --nat-gateway-id "$$nat" --region "$${AWS_REGION}" > /dev/null; \
				aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$$nat" --region "$${AWS_REGION}"; \
				echo "  ✅ NAT Gateway deleted"; \
				if [ -n "$$EIP" ] && [ "$$EIP" != "None" ]; then \
					aws ec2 release-address --allocation-id "$$EIP" --region "$${AWS_REGION}" 2>/dev/null \
						&& echo "  ✅ EIP $$EIP released" || echo "  ⚠️  Could not release EIP $$EIP (may be shared)"; \
				fi; \
			done; \
			echo "--- Deleting EKS cluster '$$CLUSTER_NAME' ---"; \
			aws eks delete-cluster --name "$$CLUSTER_NAME" --region "$${AWS_REGION}" > /dev/null; \
			aws eks wait cluster-deleted --name "$$CLUSTER_NAME" --region "$${AWS_REGION}"; \
			echo "✅ Cluster deleted"; \
			if [ -n "$$VPC_ID" ] && [ "$$VPC_ID" != "None" ]; then \
				echo "--- Cleaning up VPC '$$VPC_ID' ---"; \
				for igw in $$(aws ec2 describe-internet-gateways --region "$${AWS_REGION}" \
					--filters "Name=attachment.vpc-id,Values=$$VPC_ID" \
					--query 'InternetGateways[*].InternetGatewayId' --output text | tr '\t' '\n'); do \
					aws ec2 detach-internet-gateway --internet-gateway-id "$$igw" --vpc-id "$$VPC_ID" --region "$${AWS_REGION}" 2>/dev/null || true; \
					aws ec2 delete-internet-gateway --internet-gateway-id "$$igw" --region "$${AWS_REGION}" && echo "  ✅ IGW $$igw deleted"; \
				done; \
				for subnet in $$(aws ec2 describe-subnets --region "$${AWS_REGION}" \
					--filters "Name=vpc-id,Values=$$VPC_ID" \
					--query 'Subnets[*].SubnetId' --output text | tr '\t' '\n'); do \
					aws ec2 delete-subnet --subnet-id "$$subnet" --region "$${AWS_REGION}" 2>/dev/null && echo "  ✅ Subnet $$subnet deleted" || true; \
				done; \
				for rt in $$(aws ec2 describe-route-tables --region "$${AWS_REGION}" \
					--filters "Name=vpc-id,Values=$$VPC_ID" \
					--query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text | tr '\t' '\n'); do \
					aws ec2 delete-route-table --route-table-id "$$rt" --region "$${AWS_REGION}" 2>/dev/null && echo "  ✅ Route table $$rt deleted" || true; \
				done; \
				for sg in $$(aws ec2 describe-security-groups --region "$${AWS_REGION}" \
					--filters "Name=vpc-id,Values=$$VPC_ID" \
					--query "SecurityGroups[?GroupName!='default'].GroupId" --output text | tr '\t' '\n'); do \
					INGRESS=$$(aws ec2 describe-security-groups --region "$${AWS_REGION}" --group-ids "$$sg" \
						--query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null); \
					[ "$$INGRESS" != "[]" ] && [ -n "$$INGRESS" ] && \
						aws ec2 revoke-security-group-ingress --group-id "$$sg" --region "$${AWS_REGION}" \
							--ip-permissions "$$INGRESS" > /dev/null 2>/dev/null || true; \
					EGRESS=$$(aws ec2 describe-security-groups --region "$${AWS_REGION}" --group-ids "$$sg" \
						--query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null); \
					[ "$$EGRESS" != "[]" ] && [ -n "$$EGRESS" ] && \
						aws ec2 revoke-security-group-egress --group-id "$$sg" --region "$${AWS_REGION}" \
							--ip-permissions "$$EGRESS" > /dev/null 2>/dev/null || true; \
					aws ec2 delete-security-group --group-id "$$sg" --region "$${AWS_REGION}" 2>/dev/null \
						&& echo "  ✅ SG $$sg deleted" || echo "  ⚠️  SG $$sg skipped"; \
				done; \
				aws ec2 delete-vpc --vpc-id "$$VPC_ID" --region "$${AWS_REGION}" \
					&& echo "✅ VPC $$VPC_ID deleted" || echo "❌ VPC $$VPC_ID could not be deleted — check for remaining dependencies"; \
			fi; \
			echo ""; \
			echo "✅ Manual AWS CLI cleanup complete"; \
			exit 0; \
		fi; \
	fi
	@cd tests/integration/terraform/aws && \
		terraform destroy -auto-approve \
			-var="aws_region=$${AWS_REGION}" \
			-var="cluster_name=$${EKS_CLUSTER_NAME:-boundary-k8s-cluster-1}" \
			-var="k8s_version=$${K8S_VERSION:-1.31}" \
			-var="node_type=$${TF_NODE_TYPE:-t3.medium}" \
			-var="node_desired=$${TF_NODE_DESIRED:-2}" \
			-var="node_min=$${TF_NODE_MIN:-1}" \
			-var="node_max=$${TF_NODE_MAX:-3}" \
			-var="lbc_chart_version=$${TF_LBC_CHART_VERSION:-1.8.1}" \
			-var="allowed_public_access_cidrs=[$${TF_ALLOWED_PUBLIC_ACCESS_CIDRS:-\"0.0.0.0/0\"}]"
	@echo ""
	@echo "✅ All EKS resources have been destroyed"
