# ================================
# PHONY Declarations
# ================================
.PHONY: help format deps clean lint
.PHONY: setup-helm setup-kubeconform setup-trivy setup-kubescape lint-helm-k8s trivy-scan kubescape-scan
.PHONY: acceptance-setup acceptance-cluster acceptance-helm acceptance-test acceptance-cleanup acceptance-full

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
	@echo "  make clean             - Clean generated files"
	@echo ""
	@echo "CI/CD targets:"
	@echo "  make setup-helm         - Install Helm for CI"
	@echo "  make setup-kubeconform  - Install Kubeconform for CI"
	@echo "  make setup-trivy        - Install Trivy for CI"
	@echo "  make setup-kubescape    - Install Kubescape for CI"
	@echo "  make lint-helm-k8s      - Run Helm lint, render templates, and K8s validation"
	@echo "  make trivy-scan         - Run security scan with Trivy"
	@echo "  make kubescape-scan     - Run security scan with Kubescape"
	@echo ""
	@echo "Acceptance Testing targets:"
	@echo "  make acceptance-setup   - Setup KIND cluster for acceptance testing"
	@echo "  make acceptance-cluster - Create/verify acceptance cluster"
	@echo "  make acceptance-helm    - Install Helm chart and run Helm tests"
	@echo "  make acceptance-test    - Run acceptance tests"
	@echo "  make acceptance-full    - Run full acceptance workflow (cluster + helm + tests)"
	@echo "  make acceptance-cleanup - Delete acceptance cluster"
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
# CI/CD Setup Targets
# ================================

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
			RISK_SCORE=$$(jq -r '.summaryDetails.score // 0' kubescape-output.json); \
			FAILED_RESOURCES=$$(jq -r '.summaryDetails.ResourceCounters.failedResources // 0' kubescape-output.json); \
			PASSED_RESOURCES=$$(jq -r '.summaryDetails.ResourceCounters.passedResources // 0' kubescape-output.json); \
			COMPLIANCE_SCORE=$$(jq -r '.summaryDetails.complianceScore // 0' kubescape-output.json); \
		else \
			echo "⚠️  jq not found, using grep fallback (less reliable)"; \
			RISK_SCORE=$$(grep -o '"score":[0-9.]*' kubescape-output.json | head -1 | cut -d':' -f2 || echo "0"); \
			FAILED_RESOURCES=$$(grep -o '"failedResources":[0-9]*' kubescape-output.json | head -1 | cut -d':' -f2 || echo "0"); \
			PASSED_RESOURCES=$$(grep -o '"passedResources":[0-9]*' kubescape-output.json | head -1 | cut -d':' -f2 || echo "0"); \
			COMPLIANCE_SCORE="N/A"; \
		fi; \
		echo "  Risk Score: $$RISK_SCORE"; \
		echo "  Compliance Score: $$COMPLIANCE_SCORE"; \
		echo "  Failed Resources: $$FAILED_RESOURCES"; \
		echo "  Passed Resources: $$PASSED_RESOURCES"; \
		echo ""; \
		if [ "$$FAILED_RESOURCES" -gt 0 ]; then \
			RISK_THRESHOLD=7; \
			if command -v awk >/dev/null 2>&1; then \
				IS_ABOVE_THRESHOLD=$$(awk -v score="$$RISK_SCORE" -v threshold="$$RISK_THRESHOLD" 'BEGIN { print (score > threshold) ? 1 : 0 }'); \
			else \
				IS_ABOVE_THRESHOLD=$$(echo "$$RISK_SCORE > $$RISK_THRESHOLD" | bc -l 2>/dev/null || echo 0); \
			fi; \
			if [ "$$IS_ABOVE_THRESHOLD" = "1" ]; then \
				echo "❌ Kubescape scan FAILED: Risk score $$RISK_SCORE is above threshold ($$RISK_THRESHOLD)"; \
				echo "   Failed resources: $$FAILED_RESOURCES"; \
				exit 1; \
			else \
				echo "⚠️  Kubescape scan completed with warnings: Risk score $$RISK_SCORE (threshold: $$RISK_THRESHOLD)"; \
				echo "   Failed resources: $$FAILED_RESOURCES"; \
			fi; \
		else \
			echo "✅ Kubescape scan passed! Risk score: $$RISK_SCORE"; \
		fi; \
	else \
		echo "⚠️  Kubescape output file not found"; \
	fi

# ================================
# Acceptance Testing Targets
# ================================

acceptance-cluster:
	@echo "================================"
	@echo "Setting up KIND Acceptance Cluster"
	@echo "================================"
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

acceptance-helm:
	@echo "================================"
	@echo "Installing Helm Chart in Acceptance Cluster"
	@echo "================================"
	@echo "Checking if Helm is installed..."
	@command -v helm >/dev/null 2>&1 || (echo "❌ Helm not found. Run 'make deps' first"; exit 1)
	@echo "✅ Helm is available"
	@echo ""
	@echo "Installing boundary-worker chart with test values..."
	@helm upgrade --install boundary-worker . \
		--namespace boundary-worker \
		--create-namespace \
		--kube-context kind-acceptance \
		--set worker.service.proxy.type=NodePort \
		--set worker.persistence.recording.storageClass=standard \
		--set worker.persistence.authStorage.storageClass=standard \
		--set worker.config="listener \"tcp\" { purpose = \"proxy\" address = \"0.0.0.0:9202\" }" \
		--wait \
		--timeout 10m
	@echo "✅ Helm chart installed successfully"
	@echo ""
	@echo "Deployed resources:"
	@kubectl get all -n boundary-worker --context kind-acceptance
	@echo ""
	@echo "================================"
	@echo "Running Helm Tests"
	@echo "================================"
	@echo "Running Helm test pods in boundary-worker namespace..."
	@helm test boundary-worker \
		--namespace boundary-worker \
		--kube-context kind-acceptance \
		--timeout 10m \
		--logs
	@echo "✅ Helm tests completed successfully"

acceptance-test:
	@echo "================================"
	@echo "Running Acceptance Tests"
	@echo "================================"
	@if [ ! -f tests/acceptance/acceptance-test.sh ]; then \
		echo "❌ Test script not found: tests/acceptance/acceptance-test.sh"; \
		exit 1; \
	fi
	@bash tests/acceptance/acceptance-test.sh

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

acceptance-setup: acceptance-cluster
	@echo ""
	@echo "================================"
	@echo "✅ Acceptance Environment Ready!"
	@echo "================================"
	@echo ""
	@echo "Next steps:"
	@echo "  - Install Helm chart: make acceptance-helm"
	@echo "  - Run tests: make acceptance-test"
	@echo "  - Full workflow: make acceptance-full"
	@echo "  - Cleanup: make acceptance-cleanup"

acceptance-full: acceptance-cluster acceptance-helm acceptance-test
	@echo ""
	@echo "================================"
	@echo "✅ Full Acceptance Test Completed!"
	@echo "================================"
	@echo ""
	@echo "To cleanup, run: make acceptance-cleanup"