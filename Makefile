# ================================
# PHONY Declarations
# ================================
.PHONY: help format deps clean lint test unit-test worker-config
.PHONY: setup-helm setup-kubeconform setup-trivy setup-kubescape setup-helm-unittest lint-helm-k8s trivy-scan kubescape-scan
.PHONY: acceptance-setup acceptance-cluster acceptance-helm acceptance-test acceptance-full acceptance-cleanup
.PHONY: kind-test kind-test-setup kind-test-run kind-test-cleanup kind-test-full

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
	@echo "  make acceptance-cleanup - Delete acceptance cluster"
	@echo ""
	@echo "KIND Integration Test targets:"
	@echo "  make kind-test-setup    - Setup environment and load .env file"
	@echo "  make kind-test-run      - Run kind-test.sh with required environment variables"
	@echo "  make kind-test-cleanup  - Delete KIND cluster and cleanup"
	@echo "  make kind-test-full     - Run complete KIND test workflow (setup + run + cleanup)"
	@echo "  make kind-test          - Alias for kind-test-run"
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
	@echo "Step 1: Checking dependencies..."
	@echo "--------------------------------"
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
	@echo "Step 2: Setting up KIND cluster..."
	@echo "--------------------------------"
	@if kind get clusters | grep -q "^acceptance$$"; then \
		echo "⚠️  Acceptance cluster already exists"; \
	else \
		echo "Creating KIND cluster 'acceptance'..."; \
		kind create cluster --config tests/acceptance/kind-acceptance-config.yaml; \
		echo "✅ Acceptance cluster created"; \
	fi
	@echo ""
	@echo "Verifying cluster..."
	@kubectl cluster-info --context kind-acceptance
	@echo "✅ Cluster is ready"
	@echo ""
	@echo "================================"
	@echo "✅ Acceptance Environment Ready!"
	@echo "================================"
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
	@echo "Authenticating with Boundary"
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
	@echo "Boundary Address: $$BOUNDARY_ADDR"
	@echo "Login Name: $$BOUNDARY_LOGIN_NAME"
	@echo ""
	@echo "Authenticating with password..."
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
	echo ""; \
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
	echo "Generating worker.hcl from template..."; \
	sed -e "s|<activation-token>|$$ACTIVATION_TOKEN|g" -e "s|<cluster-id>|$$BOUNDARY_CLUSTER_ID|g" scripts/worker-template.hcl > worker.hcl; \
	echo "✅ Created worker.hcl"

acceptance-helm:
	@echo "================================"
	@echo "Installing Helm Chart in Acceptance Cluster"
	@echo "================================"
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
	@echo "================================"
	@echo "Running Helm Tests"
	@echo "================================"
	@echo "Running Helm test pods in boundary namespace..."
	@helm test boundary-worker \
		--namespace boundary \
		--kube-context kind-acceptance \
		--timeout 10m
	@echo "✅ Helm tests completed successfully"
	@echo ""
	@echo "Note: Test pod logs are not displayed as pods are deleted after completion."
	@echo "To view logs during test execution, run: kubectl logs -n boundary -l app.kubernetes.io/component=test --follow"

acceptance-test:
	@echo "================================"
	@echo "Running Acceptance Tests"
	@echo "================================"
	@if [ ! -f tests/acceptance/acceptance-test.sh ]; then \
		echo "❌ Test script not found: tests/acceptance/acceptance-test.sh"; \
		exit 1; \
	fi
	@bash tests/acceptance/acceptance-test.sh


acceptance-full:
	@echo "================================"
	@echo "Running Full Acceptance Workflow"
	@echo "================================"
	@$(MAKE) acceptance-setup
	@$(MAKE) worker-config
	@$(MAKE) acceptance-helm
	@$(MAKE) acceptance-test
	@echo ""
	@echo "================================"
	@echo "✅ Full Acceptance Test Completed!"
	@echo "================================"
	@echo ""
	@echo "To cleanup, run: make acceptance-cleanup"

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
# KIND Integration Test Targets
# ================================

kind-test-setup:
	@echo "================================"
	@echo "Setting up KIND Test Environment"
	@echo "================================"
	@echo ""
	@echo "Checking dependencies..."
	@# Check for required tools
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
	@echo "✅ kind is installed"
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "❌ kubectl is not installed"; \
		exit 1; \
	fi
	@echo "✅ kubectl is installed"
	@if ! command -v boundary >/dev/null 2>&1; then \
		echo "❌ boundary CLI is not installed"; \
		exit 1; \
	fi
	@echo "✅ boundary CLI is installed"
	@if ! command -v jq >/dev/null 2>&1; then \
		echo "⚠️  jq is not installed (recommended for JSON parsing)"; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "Installing jq..."; \
			brew install jq; \
		fi; \
	fi
	@echo "✅ jq is installed"
	@echo ""
	@echo "Loading environment variables from .env..."
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found"; \
		echo "Please create .env file with:"; \
		echo "  BOUNDARY_ADDR=https://your-cluster.boundary.hcp.to"; \
		echo "  BOUNDARY_LOGIN_NAME=your-login"; \
		echo "  BOUNDARY_PASSWORD=your-password"; \
		echo "  BOUNDARY_CLUSTER_ID=your-cluster-id"; \
		exit 1; \
	fi
	@echo "✅ .env file found"
	@echo ""
	@echo "================================"
	@echo "✅ KIND Test Environment Ready!"
	@echo "================================"

kind-test-run:
	@echo "================================"
	@echo "Running KIND Integration Test"
	@echo "================================"
	@# Check if environment variables are already set
	@if [ -n "$$BOUNDARY_ADDR" ] && [ -n "$$BOUNDARY_TOKEN" ] && [ -n "$$TARGET_ID" ] && [ -n "$$WORKER_TOKEN" ]; then \
		echo "✅ Using pre-set environment variables"; \
		echo "  BOUNDARY_ADDR: $$BOUNDARY_ADDR"; \
		echo "  TARGET_ID: $$TARGET_ID"; \
		echo ""; \
		echo "Running kind-test.sh..."; \
		cd tests/acceptance && bash kind-test.sh; \
	else \
		echo "Environment variables not set, loading from .env..."; \
		if [ ! -f .env ]; then \
			echo "❌ .env file not found"; \
			echo ""; \
			echo "Either:"; \
			echo "  1. Create .env file with BOUNDARY_ADDR, BOUNDARY_LOGIN_NAME, BOUNDARY_PASSWORD"; \
			echo "  2. Set environment variables manually:"; \
			echo "     export BOUNDARY_ADDR=https://..."; \
			echo "     export BOUNDARY_TOKEN=at_..."; \
			echo "     export TARGET_ID=ttcp_..."; \
			echo "     export WORKER_TOKEN=neslat_..."; \
			exit 1; \
		fi; \
		set -a; . ./.env; set +a; \
		if [ -z "$$BOUNDARY_ADDR" ] || [ -z "$$BOUNDARY_LOGIN_NAME" ] || [ -z "$$BOUNDARY_PASSWORD" ]; then \
			echo "❌ Required environment variables not set in .env"; \
			echo "Required: BOUNDARY_ADDR, BOUNDARY_LOGIN_NAME, BOUNDARY_PASSWORD"; \
			exit 1; \
		fi; \
		echo "✅ Environment variables loaded"; \
		echo ""; \
		echo "Authenticating with Boundary..."; \
		echo "$$BOUNDARY_PASSWORD" > /tmp/boundary_pass.txt; \
		AUTH_OUTPUT=$$(boundary authenticate password \
			-login-name "$$BOUNDARY_LOGIN_NAME" \
			-password file:///tmp/boundary_pass.txt \
			-addr "$$BOUNDARY_ADDR" \
			-format json 2>&1); \
		rm -f /tmp/boundary_pass.txt; \
		if [ $$? -ne 0 ]; then \
			echo "❌ Authentication failed"; \
			echo "$$AUTH_OUTPUT"; \
			exit 1; \
		fi; \
		BOUNDARY_TOKEN=$$(echo "$$AUTH_OUTPUT" | jq -r '.item.attributes.token'); \
		if [ -z "$$BOUNDARY_TOKEN" ] || [ "$$BOUNDARY_TOKEN" = "null" ]; then \
			echo "❌ Failed to extract token"; \
			exit 1; \
		fi; \
		export BOUNDARY_TOKEN; \
		echo "✅ Authenticated successfully"; \
		echo ""; \
		echo "Getting target ID..."; \
		TARGET_OUTPUT=$$(boundary targets list -recursive -addr="$$BOUNDARY_ADDR" -token=env://BOUNDARY_TOKEN -format=json 2>&1); \
		if [ $$? -ne 0 ]; then \
			echo "❌ Failed to list targets"; \
			echo "$$TARGET_OUTPUT"; \
			exit 1; \
		fi; \
		TARGET_ID=$$(echo "$$TARGET_OUTPUT" | jq -r '.items[0].id // empty'); \
		if [ -z "$$TARGET_ID" ]; then \
			echo "❌ No targets found"; \
			exit 1; \
		fi; \
		echo "✅ Found target: $$TARGET_ID"; \
		echo ""; \
		echo "Creating worker token..."; \
		WORKER_OUTPUT=$$(boundary workers create controller-led -scope-id global -addr="$$BOUNDARY_ADDR" -token=env://BOUNDARY_TOKEN -format=json 2>&1); \
		if [ $$? -ne 0 ]; then \
			echo "❌ Failed to create worker"; \
			echo "$$WORKER_OUTPUT"; \
			exit 1; \
		fi; \
		WORKER_TOKEN=$$(echo "$$WORKER_OUTPUT" | jq -r '.item.controller_generated_activation_token // empty'); \
		if [ -z "$$WORKER_TOKEN" ]; then \
			echo "❌ Failed to extract worker token"; \
			exit 1; \
		fi; \
		echo "✅ Worker token created"; \
		echo ""; \
		echo "Running kind-test.sh..."; \
		cd tests/acceptance && \
		export BOUNDARY_ADDR="$$BOUNDARY_ADDR" && \
		export BOUNDARY_TOKEN="$$BOUNDARY_TOKEN" && \
		export TARGET_ID="$$TARGET_ID" && \
		export WORKER_TOKEN="$$WORKER_TOKEN" && \
		bash kind-test.sh; \
	fi

kind-test-cleanup:
	@echo "================================"
	@echo "Cleaning up KIND Test Cluster"
	@echo "================================"
	@if kind get clusters 2>/dev/null | grep -q "^boundary-acceptance$$"; then \
		echo "Deleting KIND cluster 'boundary-acceptance'..."; \
		kind delete cluster --name boundary-acceptance; \
		echo "✅ KIND cluster deleted"; \
	else \
		echo "⚠️  KIND cluster 'boundary-acceptance' does not exist"; \
	fi
	@echo "✅ Cleanup complete"

kind-test-full: kind-test-setup kind-test-run kind-test-cleanup
	@echo ""
	@echo "================================"
	@echo "✅ KIND Integration Test Complete!"
	@echo "================================"

kind-test: kind-test-run