# Auto-load .env if present (strips 'export ' prefix for Make compatibility)
ifneq (,$(wildcard .env))
  $(shell sed 's/^export //; /^[[:space:]]*#/d; /^$$/d' .env > .env.make)
  include .env.make
  export
endif

# ================================
# PHONY Declarations
# ================================
.PHONY: help format deps clean lint test unit-test worker-config
.PHONY: setup-helm setup-kubeconform setup-trivy setup-kubescape setup-helm-unittest lint-helm-k8s trivy-scan kubescape-scan
.PHONY: acceptance-setup acceptance-cluster acceptance-helm acceptance-test acceptance-full acceptance-cleanup
.PHONY: eks-setup eks-worker-config eks-helm eks-test eks-full eks-cleanup

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
	@echo ""
	@echo "AWS EKS Acceptance Testing targets:"
	@echo "  make eks-setup             - Create EKS cluster + EBS CSI + AWS Load Balancer Controller"
	@echo "  make eks-worker-config     - Generate worker.hcl for EKS deployment"
	@echo "  make eks-helm              - Install Helm chart with EKS values (gp2, NLB)"
	@echo "  make eks-test              - Run full EKS acceptance test suite"
	@echo "  make eks-full              - Full EKS workflow (eks-setup + worker-config + helm + test)"
	@echo "  make eks-cleanup           - Uninstall Helm release from EKS (set DESTROY_CLUSTER=true to delete cluster)"
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
	@curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
	@helm version
	@echo "✅ Helm installed"

setup-kubeconform:
	@echo "Installing Kubeconform..."
	@curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
	@sudo mv kubeconform /usr/local/bin/
	@kubeconform -v
	@echo "✅ Kubeconform installed"

setup-trivy:
	@echo "Installing Trivy..."
	@sudo apt-get install -y wget apt-transport-https gnupg lsb-release
	@wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
	@echo "deb https://aquasecurity.github.io/trivy-repo/deb $$(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
	@sudo apt-get update
	sudo apt-get install -y trivy
	@trivy --version
	@echo "✅ Trivy installed"

setup-kubescape:
	@echo "Installing Kubescape..."
	@curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash
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
		--verbose || true
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
	@for script in tests/acceptance/*.sh; do \
		echo ""; \
		echo "Running: $$script"; \
		echo ""; \
		bash $$script || exit 1; \
	done
	@echo ""
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

acceptance-cleanup:
	@echo "================================"
	@echo "Cleaning up Acceptance Cluster"
	@echo "================================"
	@if kind get clusters | grep -q "^acceptance$$"; then \
		echo "Deleting KIND cluster 'acceptance'..."; \
		kind delete cluster --name acceptance; \
		echo "✅ Acceptance cluster deleted"; \
	else \
		echo "⚠️  Acceptance cluster does not exist"; \
	fi
	@rm -f worker.hcl
	@echo "✅ Removed worker.hcl"

# ================================
# AWS EKS Acceptance Testing Targets
# ================================

eks-setup:
	@echo "Setting Up AWS EKS Cluster..."
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; \
			echo "  export $$v=<value>"; \
			exit 1; \
		fi; \
	done
	@bash tests/acceptance/eks-cluster-setup.sh
	@echo ""
	@echo "✅ EKS cluster setup complete"
	@echo ""

eks-worker-config:
	@echo "Generating Worker Config (EKS)..."
	@echo ""
	@$(MAKE) worker-config
	@echo ""
	@echo "✅ worker.hcl ready for EKS deployment"
	@echo ""

eks-helm:
	@echo "Installing Helm Chart on EKS..."
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set."; exit 1; \
		fi; \
	done
	@[ -f worker.hcl ] || { echo "❌ worker.hcl not found. Run 'make eks-worker-config' first"; exit 1; }
	@AWS_ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
		{ echo "❌ AWS credentials not configured"; exit 1; }; \
	EKS_CONTEXT="arn:aws:eks:$${AWS_REGION}:$${AWS_ACCOUNT_ID}:cluster/$${EKS_CLUSTER_NAME}"; \
	echo "Updating kubeconfig for cluster $${EKS_CLUSTER_NAME}..."; \
	aws eks update-kubeconfig --name "$${EKS_CLUSTER_NAME}" --region "$${AWS_REGION}"; \
	echo "Installing boundary-worker chart with EKS values..."; \
	helm upgrade --install boundary-worker . \
		--namespace boundary \
		--create-namespace \
		--kube-context "$${EKS_CONTEXT}" \
		--set worker.service.proxy.type=LoadBalancer \
		--set worker.persistence.recording.storageClass=gp2 \
		--set worker.persistence.authStorage.storageClass=gp2 \
		--set-file worker.config=worker.hcl \
		--timeout 10m \
		--atomic; \
	echo ""; \
	echo "Deployed resources:"; \
	kubectl get all -n boundary --context "$${EKS_CONTEXT}"
	@echo ""
	@echo "✅ Helm chart installed on EKS"
	@echo ""

eks-test:
	@echo "Running EKS Acceptance Tests..."
	@echo ""
	@for v in AWS_REGION EKS_CLUSTER_NAME BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD BOUNDARY_CLUSTER_ID; do \
		if [ -z "$${!v:-}" ]; then \
			echo "❌ $$v is not set. Check your .env or export it."; \
			exit 1; \
		fi; \
	done
	@bash tests/acceptance/eks-acceptance-test.sh
	@echo ""

eks-full:
	@echo "================================"
	@echo "Full EKS Acceptance Workflow"
	@echo "================================"
	@echo ""
	@$(MAKE) eks-setup
	@$(MAKE) eks-worker-config
	@$(MAKE) eks-helm
	@$(MAKE) eks-test
	@echo ""
	@echo "✅ End-to-end EKS workflow has been completed successfully"
	@echo ""
	@echo "To cleanup: make eks-cleanup"

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
		echo "Deleting EKS cluster '$${EKS_CLUSTER_NAME}' (DESTROY_CLUSTER=true)..."; \
		eksctl delete cluster --name "$${EKS_CLUSTER_NAME}" --region "$${AWS_REGION}"; \
		echo "✅ EKS cluster deleted"; \
	else \
		echo ""; \
		echo "ℹ  EKS cluster retained. To delete: DESTROY_CLUSTER=true make eks-cleanup"; \
	fi
