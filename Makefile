.PHONY: help lint lint-helm lint-templates lint-k8s lint-yaml lint-security format deps clean
.PHONY: ci-setup-helm ci-setup-kubeconform ci-setup-trivy ci-lint-helm-k8s ci-lint-security

# Default target
help:
	@echo "================================"
	@echo "Boundary Worker Helm Chart - Lint Targets"
	@echo "================================"
	@echo "Available targets:"
	@echo "  make lint              - Run all lint checks"
	@echo "  make lint-helm         - Run Helm lint"
	@echo "  make lint-templates    - Render Helm templates"
	@echo "  make lint-k8s          - Run Kubernetes validation"
	@echo "  make lint-yaml         - Run YAML lint"
	@echo "  make lint-security     - Run security scan with Trivy"
	@echo "  make format            - Format all YAML files with Prettier"
	@echo "  make deps              - Install required tools (macOS)"
	@echo "  make clean             - Clean generated files"
	@echo ""
	@echo "CI/CD targets:"
	@echo "  make ci-setup-helm         - Install Helm for CI"
	@echo "  make ci-setup-kubeconform  - Install Kubeconform for CI"
	@echo "  make ci-setup-trivy        - Install Trivy for CI"
	@echo "  make ci-lint-helm-k8s      - Run Helm lint, render templates, and K8s validation"
	@echo "  make ci-lint-security      - Run security scan with Trivy"
	@echo "================================"

# Install required tools (macOS with Homebrew)
deps:
	@echo "Installing required tools..."
	@command -v helm >/dev/null 2>&1 || brew install helm
	@command -v kubeconform >/dev/null 2>&1 || brew install kubeconform
	@command -v yamllint >/dev/null 2>&1 || brew install yamllint
	@command -v trivy >/dev/null 2>&1 || brew install trivy
	@command -v prettier >/dev/null 2>&1 || npm install -g prettier
	@echo "✅ All tools installed"

# Run all lint checks
lint: lint-helm lint-templates lint-k8s lint-yaml lint-security
	@echo ""
	@echo "================================"
	@echo "Lint Summary"
	@echo "================================"
	@echo "All lint checks completed!"
	@echo "Check output above for any warnings or errors"
	@echo "================================"

# 1. Helm Lint
lint-helm:
	@echo "================================"
	@echo "Step 1: Running Helm Lint"
	@echo "================================"
	@helm lint . || (echo "❌ Helm lint failed" && exit 1)
	@echo "✅ Helm lint passed"
	@echo ""

# 2. Render Templates
lint-templates:
	@echo "================================"
	@echo "Step 2: Rendering Helm Templates"
	@echo "================================"
	@helm template boundary-worker . > rendered.yaml || (echo "❌ Template rendering failed" && exit 1)
	@echo "✅ Templates rendered successfully ($(shell wc -l < rendered.yaml) lines)"
	@echo ""

# 3. Kubernetes Validation
lint-k8s: lint-templates
	@echo "================================"
	@echo "Step 3: Kubernetes Validation"
	@echo "================================"
	@kubeconform -strict rendered.yaml || (echo "❌ Kubernetes validation failed" && exit 1)
	@echo "✅ Kubernetes validation passed"
	@echo ""

# 4. YAML Lint
# lint-yaml:
# 	@echo "================================"
# 	@echo "Step 4: YAML Lint"
# 	@echo "================================"
# 	@yamllint . 2>&1 | tee yamllint-output.txt; \
# 	EXIT_CODE=$$?; \
# 	ERROR_COUNT=$$(grep -c "error" yamllint-output.txt 2>/dev/null || echo 0); \
# 	WARNING_COUNT=$$(grep -c "warning" yamllint-output.txt 2>/dev/null || echo 0); \
# 	echo ""; \
# 	if [ $$ERROR_COUNT -gt 0 ]; then \
# 		echo "❌ YAML lint FAILED: $$ERROR_COUNT errors, $$WARNING_COUNT warnings"; \
# 		exit 1; \
# 	elif [ $$WARNING_COUNT -gt 0 ]; then \
# 		echo "⚠️  YAML lint WARNING: $$WARNING_COUNT warnings"; \
# 	else \
# 		echo "✅ YAML lint passed"; \
# 	fi; \
# 	echo ""

# 5. Security Scan
lint-security: lint-templates
	@echo "================================"
	@echo "Step 5: Security Scan with Trivy"
	@echo "================================"
	@trivy config rendered.yaml --exit-code 0 2>&1 | tee trivy-output.txt; \
	CRITICAL_COUNT=$$(grep -E 'CRITICAL: [0-9]+' trivy-output.txt | sed -E 's/.*CRITICAL: ([0-9]+).*/\1/' | head -1); \
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
		echo "⚠️  Security scan WARNING: $$MEDIUM_COUNT MEDIUM, $$LOW_COUNT LOW issues"; \
	else \
		echo "✅ Security scan passed"; \
	fi; \
	echo ""

# Format all YAML files with Prettier
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

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -f rendered.yaml yamllint-output.txt trivy-output.txt
	@echo "✅ Clean complete"

# ================================
# CI/CD Targets
# ================================

# Install Helm for CI (Linux)
ci-setup-helm:
	@echo "Installing Helm..."
	@curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
	@helm version
	@echo "✅ Helm installed"

# Install Kubeconform for CI (Linux)
ci-setup-kubeconform:
	@echo "Installing Kubeconform..."
	@curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
	@sudo mv kubeconform /usr/local/bin/
	@kubeconform -v
	@echo "✅ Kubeconform installed"

# Install Trivy for CI (Linux/Ubuntu)
ci-setup-trivy:
	@echo "Installing Trivy..."
	@sudo apt-get install -y wget apt-transport-https gnupg lsb-release
	@wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
	@echo "deb https://aquasecurity.github.io/trivy-repo/deb $$(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
	@sudo apt-get update
	sudo apt-get install -y trivy
	@trivy --version
	@echo "✅ Trivy installed"

# CI: Helm Lint + Template Rendering + Kubernetes Validation
ci-lint-helm-k8s:
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

# CI: Security Scan with Trivy
ci-lint-security:
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