# ────────────────────────────────────────────────────────────────────────────────
# CLI Detection
# ────────────────────────────────────────────────────────────────────────────────
KUBE_CLI ?= $(shell command -v oc >/dev/null 2>&1 && echo oc || echo kubectl)
CLUSTER_TYPE ?= $(shell command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1 && echo openshift || echo kubernetes)
export KUBE_CLI CLUSTER_TYPE

# ────────────────────────────────────────────────────────────────────────────────
# Color Definitions
# ────────────────────────────────────────────────────────────────────────────────
RESET := \033[0m
BOLD := \033[1m
DIM := \033[2m

# Text Colors
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
MAGENTA := \033[35m
CYAN := \033[36m
WHITE := \033[37m

# Background Colors
BG_RED := \033[41m
BG_GREEN := \033[42m
BG_YELLOW := \033[43m
BG_BLUE := \033[44m

# ────────────────────────────────────────────────────────────────────────────────
# Target Definitions
# ────────────────────────────────────────────────────────────────────────────────
.PHONY: all help banner preflight lint fmt test-unit _require-shfmt install-cert-manager-operator install-cert-manager-helm install-pebble \
        install-fake-dns install-all install-monitoring create-issuer create-dns01-issuer \
        create-selfsigned-issuer create-certs create-apiserver-cert verify-apiserver-cert \
        test-all test-dns01 quick-http-test quick-dns-test quick-selfsigned-test \
        test-cert verify-cert test-cert-renewal clean-cert-renewal test-ingress-tls clean-ingress-test \
        status \
        troubleshoot check-cert check-cert-renewal check-issuer verify-monitoring check-network check-network-stack check-workload-partitioning \
        diagnose-http01 diagnose-dns01 clean clean-certs clean-pebble clean-fake-dns \
        clean-dns-config clean-issuers clean-selfsigned clean-monitoring clean-temp \
        delete-certificate delete-issuer \
        clean-acmedns clean-challtestsrv \
        uninstall-cert-manager-operator uninstall-monitoring uninstall-all \
        install-minio install-oadp install-ibu-prereqs capture-cert-state \
        test-ibu-certs test-ibu-preserved test-ibu-both quick-ibu-test clean-ibu \
        create-multi-algo-certs verify-key-formats test-ibu-multi-algo clean-multi-algo-certs \
        quick-multi-algo-test \
        install-pebble-challtestsrv install-local-dns register-acmedns \
        label-cert-resources simulate-ibu validate-cert-loss validate-post-restore \
        validate-yaml

# Default target
all: help

# ────────────────────────────────────────────────────────────────────────────────
# Main Targets
# ────────────────────────────────────────────────────────────────────────────────

banner:
	@echo ""
	@echo "$(CYAN)$(BOLD)"
	@echo "  ╔═══════════════════════════════════════════════════════════════╗"
	@echo "  ║         CERT-MANAGER SCRIPTS TOOLKIT              ║"
	@echo "  ║             OpenShift Automation                              ║"
	@echo "  ╚═══════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"

help: banner ## Show this help message
	@echo "$(BOLD)$(BLUE)Available Commands:$(RESET)"
	@echo ""
	@echo "$(YELLOW)Setup & Validation:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(preflight|lint|fmt|test-unit|validate-yaml|check-network|check-workload)"
	@echo ""
	@echo "$(YELLOW)Installation:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(install-|register-)"
	@echo ""
	@echo "$(YELLOW)Issuers & Certificates:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(create-|test-cert|verify-)"
	@echo ""
	@echo "$(YELLOW)Quick Tests:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(quick-|test-all|test-dns01|test-cert-renewal|test-ingress)"
	@echo ""
	@echo "$(YELLOW)Status & Troubleshooting:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(status|troubleshoot|diagnose|check-cert|check-issuer|verify-monitoring)"
	@echo ""
	@echo "$(YELLOW)IBU Testing:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(ibu|minio|oadp|label-cert|validate-cert|validate-post)"
	@echo ""
	@echo "$(YELLOW)Cleanup:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(delete-|clean|uninstall)"
	@echo ""
	@echo "$(DIM)Usage: make <command>$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# Setup & Validation
# ────────────────────────────────────────────────────────────────────────────────

preflight: ## Check all dependencies and prerequisites
	@./scripts/preflight-check.sh
	@echo ""

lint: _require-shfmt ## Check shell script formatting with shfmt and shellcheck
	@echo "$(BOLD)$(BLUE)Linting Bash scripts...$(RESET)"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "$(RED)shellcheck not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shellcheck$(RESET)"; \
	  echo "$(DIM)  Linux: apt-get install shellcheck or dnf install ShellCheck$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(DIM)  Running shellcheck...$(RESET)"
	@find . -name '*.sh' -type f -not -path './venv/*' | xargs shellcheck -e SC1091,SC2034,SC2329 || (echo "$(RED)shellcheck failed!$(RESET)" && exit 1)
	@echo "$(DIM)  Running shfmt...$(RESET)"
	@shfmt -d scripts/ lib/ || (echo "$(RED)shfmt formatting check failed!$(RESET)" && echo "$(YELLOW)To fix: make fmt$(RESET)" && exit 1)
	@echo "$(GREEN)Bash linting passed!$(RESET)"

fmt: _require-shfmt ## Auto-fix shell script formatting with shfmt
	@echo "$(BOLD)$(BLUE)Formatting shell scripts...$(RESET)"
	@shfmt -w scripts/ lib/
	@echo "$(GREEN)Shell scripts formatted!$(RESET)"

test-unit: ## Run BATS unit tests (no cluster)
	@if ! command -v bats >/dev/null 2>&1; then \
	  echo "$(RED)bats not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install bats-core$(RESET)"; \
	  echo "$(DIM)  Linux: see https://github.com/bats-core/bats-core#install$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(BLUE)Running BATS unit tests...$(RESET)"
	@bats --recursive tests/
	@echo "$(GREEN)Unit tests passed!$(RESET)"

validate-yaml: ## Validate YAML manifests with kubeconform
	@./scripts/workflows/validate-yaml.sh

_require-shfmt:
	@if ! command -v shfmt >/dev/null 2>&1; then \
	  echo "$(RED)shfmt not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shfmt$(RESET)"; \
	  echo "$(DIM)  Linux: go install mvdan.cc/sh/v3/cmd/shfmt@latest$(RESET)"; \
	  exit 1; \
	fi

check-network: ## Check cluster network configuration (IPv4/IPv6/Dual-stack)
	@./scripts/check-cluster-network.sh

check-network-stack: ## Detect and verify IPv4/IPv6/dual-stack cluster configuration
	@./scripts/troubleshooting/check-network-stack.sh

check-workload-partitioning: ## Verify cert-manager pods are not using workload partitioning
	@./scripts/troubleshooting/check-workload-partitioning.sh

# ────────────────────────────────────────────────────────────────────────────────
# Installation
# ────────────────────────────────────────────────────────────────────────────────

install-cert-manager-operator: ## Install cert-manager Operator for Red Hat OpenShift
	@echo "$(BOLD)$(BLUE)Installing cert-manager Operator...$(RESET)"
	@./scripts/install-cert-manager-operator.sh
	@echo "$(GREEN)cert-manager Operator installation completed!$(RESET)"
	@echo ""

install-cert-manager-helm: ## Install cert-manager via Helm (vanilla Kubernetes)
	@echo "$(BOLD)$(BLUE)Installing cert-manager via Helm...$(RESET)"
	@./scripts/install-cert-manager-helm.sh
	@echo "$(GREEN)cert-manager Helm installation completed!$(RESET)"
	@echo ""

install-pebble: ## Install Pebble ACME test server
	@echo "$(BOLD)$(BLUE)Installing Pebble ACME test server...$(RESET)"
	@./scripts/install-pebble.sh
	@echo ""

install-fake-dns: ## Install fake DNS API for air-gapped DNS-01 testing
	@echo "$(BOLD)$(BLUE)Installing fake DNS API for air-gapped testing...$(RESET)"
	@./scripts/install-fake-dns.sh
	@echo ""

install-monitoring: ## Install cert-manager Prometheus monitoring and alerts
	@./scripts/install-monitoring.sh

install-pebble-challtestsrv: ## Install Pebble challenge test server for DNS-01
	@echo "$(BOLD)$(BLUE)Installing Pebble challenge test server...$(RESET)"
	@./scripts/install-pebble-challtestsrv.sh
	@echo ""

install-local-dns: ## Install acme-dns local DNS server
	@echo "$(BOLD)$(BLUE)Installing acme-dns local DNS server...$(RESET)"
	@./scripts/install-local-dns.sh
	@echo ""

register-acmedns: ## Register acme-dns account and create credentials secret
	@./scripts/register-acmedns-account.sh

install-all: install-cert-manager-operator install-pebble ## Install cert-manager-operator and Pebble
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║         All components installed successfully!              ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"

# ────────────────────────────────────────────────────────────────────────────────
# Issuers & Certificates
# ────────────────────────────────────────────────────────────────────────────────

create-issuer: ## Create ClusterIssuer pointing to Pebble (HTTP-01)
	@./scripts/create-issuer.sh

create-dns01-issuer: ## Create ClusterIssuer pointing to Pebble (DNS-01)
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 ./scripts/create-dns01-issuer.sh

create-selfsigned-issuer: ## Create self-signed CA chain (disconnected/air-gapped)
	@./scripts/create-selfsigned-issuer.sh

create-certs: ## Create test certificates (HTTP-01)
	@./scripts/create-test-certificates.sh

create-apiserver-cert: ## Create API server certificate
	@./scripts/create-apiserver-certificate.sh

verify-apiserver-cert: ## Verify API server certificate
	@./scripts/troubleshooting/verify-apiserver-certificate.sh

test-cert: ## Create a test wildcard certificate (DNS-01)
	@echo "Creating test wildcard certificate..."
	@printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: wildcard-test\n  namespace: default\nspec:\n  secretName: wildcard-test-tls\n  issuerRef:\n    name: pebble-dns01-issuer\n    kind: ClusterIssuer\n  dnsNames:\n  - "*.example.com"\n  - "example.com"\n' | $(KUBE_CLI) apply -f -
	@echo "Certificate created. Run 'make verify-cert' to check status."

verify-cert: ## Verify certificate status
	@echo ""
	@echo "$(BOLD)Certificate Status$(RESET)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(KUBE_CLI) get certificate wildcard-test -n default 2>/dev/null || echo "Certificate not found"
	@echo ""
	@echo "Orders:"
	@$(KUBE_CLI) get order -n default 2>/dev/null || echo "No orders found"
	@echo ""
	@echo "Challenges:"
	@$(KUBE_CLI) get challenge -n default 2>/dev/null || echo "No challenges found"
	@echo ""
	@if $(KUBE_CLI) get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
		echo "$(GREEN)Certificate is READY!$(RESET)"; \
	else \
		echo "$(YELLOW)Certificate is still being issued...$(RESET)"; \
	fi

# ────────────────────────────────────────────────────────────────────────────────
# Quick Tests
# ────────────────────────────────────────────────────────────────────────────────

test-all: install-all create-issuer create-certs ## Full HTTP-01 environment setup (install operator, Pebble, issuer, certs)
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║         Complete Test Environment Ready!                    ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo ""
	@echo "You can now test certificate issuance with:"
	@echo "  oc get certificate -A"
	@echo "  oc get order,challenge -A"

test-dns01: install-fake-dns ## Complete DNS-01 setup (air-gapped)
	@echo "Creating DNS-01 issuer..."
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 ./scripts/create-dns01-issuer.sh
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║         DNS-01 Environment Ready!                           ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo ""
	@echo "Test with: make test-cert"
	@echo "Monitor progress: watch oc get certificate -n default"

quick-http-test: ## Quick end-to-end HTTP-01 test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick HTTP-01 Test Running...$(RESET)"
	@echo ""
	@if [ "$(CLUSTER_TYPE)" = "openshift" ]; then $(MAKE) install-cert-manager-operator; else $(MAKE) install-cert-manager-helm; fi
	@PEBBLE_ALWAYS_VALID=1 $(MAKE) install-pebble
	@$(MAKE) create-issuer
	@CLUSTER_DOMAIN=$$($(KUBE_CLI) get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "example.com"); \
	printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: test-cert-http01\n  namespace: default\nspec:\n  secretName: test-cert-http01-tls\n  issuerRef:\n    name: pebble-issuer\n    kind: ClusterIssuer\n  dnsNames:\n  - test.'"$$CLUSTER_DOMAIN"'\n' | $(KUBE_CLI) apply -f -
	@echo ""
	@echo "Waiting for certificate (timeout: 3 minutes)..."
	@timeout=180; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if $(KUBE_CLI) get certificate test-cert-http01 -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			echo "Quick HTTP-01 test complete! Run 'make clean' to clean up."; \
			exit 0; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done; \
	echo "$(RED)Certificate test-cert-http01 not Ready after $${timeout}s$(RESET)"; \
	$(KUBE_CLI) get certificate test-cert-http01 -n default 2>/dev/null || true; \
	exit 1

quick-selfsigned-test: create-selfsigned-issuer ## Quick end-to-end self-signed CA test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick Self-Signed CA Test Running...$(RESET)"
	@echo ""
	@CLUSTER_DOMAIN=$$($(KUBE_CLI) get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "example.com"); \
	ISSUER_NAME=$$(echo "$${CA_ISSUER_NAME:-selfsigned-ca-issuer}"); \
	printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: test-cert-selfsigned\n  namespace: default\nspec:\n  secretName: test-cert-selfsigned-tls\n  issuerRef:\n    name: '"$$ISSUER_NAME"'\n    kind: ClusterIssuer\n  dnsNames:\n  - test.'"$$CLUSTER_DOMAIN"'\n  - "*.'"$$CLUSTER_DOMAIN"'"\n' | $(KUBE_CLI) apply -f -
	@echo ""
	@echo "Waiting for certificate (timeout: 2 minutes)..."
	@timeout=120; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if $(KUBE_CLI) get certificate test-cert-selfsigned -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			echo "Quick self-signed CA test complete! Run 'make clean-selfsigned' to clean up."; \
			exit 0; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done; \
	echo "$(RED)Certificate test-cert-selfsigned not Ready after $${timeout}s$(RESET)"; \
	$(KUBE_CLI) get certificate test-cert-selfsigned -n default 2>/dev/null || true; \
	exit 1

quick-dns-test: ## Quick end-to-end DNS-01 test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick DNS-01 Test Running...$(RESET)"
	@echo ""
	@echo "Ensuring Pebble ACME server is running (required for DNS-01)..."
	@if ! $(KUBE_CLI) get deployment pebble -n pebble -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q '^[1-9]'; then \
		echo "Pebble not running — installing with PEBBLE_ALWAYS_VALID=1..."; \
		PEBBLE_ALWAYS_VALID=1 $(MAKE) install-pebble; \
	else \
		echo "Pebble is already running."; \
	fi
	@$(MAKE) install-fake-dns
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 ./scripts/create-dns01-issuer.sh
	@$(MAKE) test-cert
	@echo ""
	@echo "Waiting for certificate (timeout: 5 minutes)..."
	@timeout=300; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if $(KUBE_CLI) get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			$(MAKE) verify-cert; \
			echo "Quick DNS-01 test complete! Run 'make clean' to clean up."; \
			exit 0; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done; \
	echo "$(RED)Certificate wildcard-test not Ready after $${timeout}s$(RESET)"; \
	$(KUBE_CLI) get certificate wildcard-test -n default 2>/dev/null || true; \
	exit 1

quick-multi-algo-test: create-multi-algo-certs ## Quick multi-algorithm certificate test (ECDSA, RSA, Ed25519)
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║    Multi-Algorithm Certificate Test Complete!               ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo ""
	@echo "Run 'make clean-multi-algo-certs' to clean up."

test-cert-renewal: ## Test automatic certificate renewal with a short-lived cert
	@./scripts/test-cert-renewal.sh

test-ingress-tls: ## End-to-end TLS integration test via Route/Ingress
	@./scripts/test-ingress-tls.sh

# ────────────────────────────────────────────────────────────────────────────────
# Status
# ────────────────────────────────────────────────────────────────────────────────

status: ## Show installed components and their status
	@./scripts/status.sh

# ────────────────────────────────────────────────────────────────────────────────
# Troubleshooting
# ────────────────────────────────────────────────────────────────────────────────

troubleshoot: ## Run all troubleshooting diagnostics
	@./scripts/troubleshooting/check-all.sh

check-cert: ## Check specific certificate (CERT=name NS=namespace)
	@if [ -z "$(CERT)" ] || [ -z "$(NS)" ]; then \
		echo "$(YELLOW)Usage: make check-cert CERT=<name> NS=<namespace>$(RESET)"; \
		echo "$(DIM)Example: make check-cert CERT=test-cert NS=default$(RESET)"; \
		exit 1; \
	fi
	@./scripts/troubleshooting/check-certificate.sh $(CERT) $(NS)

check-issuer: ## Check specific ClusterIssuer (ISSUER=name)
	@if [ -z "$(ISSUER)" ]; then \
		echo "$(YELLOW)Usage: make check-issuer ISSUER=<name>$(RESET)"; \
		echo "$(DIM)Example: make check-issuer ISSUER=pebble-issuer$(RESET)"; \
		exit 1; \
	fi
	@./scripts/troubleshooting/check-issuer.sh $(ISSUER)

diagnose-http01: ## Diagnose HTTP-01 challenge issues
	@./scripts/troubleshooting/diagnose-http01.sh

diagnose-dns01: ## Diagnose DNS-01 challenge issues
	@./scripts/troubleshooting/diagnose-dns01.sh

check-cert-renewal: ## Check certificate renewal status and upcoming renewals
	@./scripts/troubleshooting/check-cert-renewal.sh $(if $(CERT),$(CERT) $(NS))

verify-monitoring: ## Verify cert-manager Prometheus monitoring setup
	@./scripts/troubleshooting/verify-monitoring.sh

# ────────────────────────────────────────────────────────────────────────────────
# IBU Testing
# ────────────────────────────────────────────────────────────────────────────────

install-minio: ## Install MinIO object storage for OADP
	@echo "$(BOLD)$(BLUE)Installing MinIO object storage...$(RESET)"
	@./scripts/ibu/install-minio.sh
	@echo ""

install-oadp: ## Install OADP operator for backup/restore
	@echo "$(BOLD)$(BLUE)Installing OADP operator...$(RESET)"
	@./scripts/ibu/install-oadp.sh
	@echo ""

install-ibu-prereqs: install-minio install-oadp ## Install IBU test prerequisites (MinIO + OADP)
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║         IBU Prerequisites Installed!                        ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"

capture-cert-state: ## Capture current certificate state for IBU testing
	@./scripts/ibu/capture-cert-state.sh

test-ibu-certs: ## Run IBU certificate loss simulation (Scenario 1)
	@echo "$(BOLD)$(BLUE)Running IBU certificate loss test (Scenario 1)...$(RESET)"
	@./scripts/ibu/run-ibu-test.sh
	@echo ""

test-ibu-preserved: ## Run IBU certificate preservation test (Scenario 2)
	@echo "$(BOLD)$(BLUE)Running IBU certificate preservation test (Scenario 2)...$(RESET)"
	@./scripts/ibu/run-ibu-preserved-test.sh
	@echo ""

test-ibu-both: ## Run both IBU scenarios (loss and preservation)
	@echo "$(BOLD)$(BLUE)Running both IBU test scenarios...$(RESET)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Scenario 1: Certificate Loss (default IBU behavior)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(MAKE) test-ibu-certs
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Scenario 2: Certificate Preservation (with LCA labels)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(MAKE) test-ibu-preserved
	@echo ""
	@echo "$(GREEN)Both IBU test scenarios completed!$(RESET)"

quick-ibu-test: install-cert-manager-operator install-ibu-prereqs ## End-to-end IBU certificate loss test
	@echo "$(BOLD)$(BLUE)Setting up test environment...$(RESET)"
	@$(MAKE) quick-dns-test || true
	@echo ""
	@echo "$(BOLD)$(BLUE)Running IBU certificate loss test...$(RESET)"
	@./scripts/ibu/run-ibu-test.sh

create-multi-algo-certs: ## Create test certs with all key algorithms (ECDSA, RSA, Ed25519)
	@echo "$(BOLD)$(BLUE)Creating multi-algorithm test certificates...$(RESET)"
	@./scripts/ibu/create-multi-algo-certs.sh
	@echo ""

verify-key-formats: ## Verify PEM key formats of TLS secrets in namespace
	@./scripts/ibu/verify-key-formats.sh

test-ibu-multi-algo: ## Run IBU cert loss test with all key algorithms
	@echo "$(BOLD)$(BLUE)Running multi-algorithm IBU certificate loss test...$(RESET)"
	@MULTI_ALGO=true ./scripts/ibu/run-ibu-test.sh
	@echo ""

label-cert-resources: ## Label cert-manager resources for IBU preservation (LCA)
	@echo "$(BOLD)$(BLUE)Labeling cert-manager resources for IBU preservation...$(RESET)"
	@./scripts/ibu/label-cert-resources.sh
	@echo ""

simulate-ibu: ## Simulate IBU via OADP backup/restore cycle
	@echo "$(BOLD)$(BLUE)Running IBU simulation via OADP backup/restore...$(RESET)"
	@./scripts/ibu/simulate-ibu-backup-restore.sh
	@echo ""

validate-cert-loss: ## Compare before/after certificate states for IBU validation
	@echo "$(BOLD)$(BLUE)Validating certificate state changes...$(RESET)"
	@./scripts/ibu/validate-cert-loss.sh
	@echo ""

validate-post-restore: ## Validate cluster health after IBU backup/restore
	@./scripts/ibu/validate-post-restore.sh

clean-multi-algo-certs: ## Clean up multi-algorithm test certificates
	@echo "$(BOLD)$(YELLOW)Cleaning up multi-algorithm test certificates...$(RESET)"
	@$(KUBE_CLI) delete certificate -n default -l app=ibu-multi-algo-test --ignore-not-found=true 2>/dev/null || true
	@$(KUBE_CLI) delete secret -n default ibu-cert-ecdsa-p256-tls ibu-cert-ecdsa-p384-tls ibu-cert-rsa-2048-tls ibu-cert-rsa-4096-tls ibu-cert-ed25519-tls --ignore-not-found=true 2>/dev/null || true
	@echo "$(GREEN)Multi-algorithm test certificates cleaned.$(RESET)"

clean-ibu: ## Clean up IBU test resources (MinIO, OADP, backups)
	@echo "$(BOLD)$(YELLOW)Cleaning up IBU test resources...$(RESET)"
	@oc delete backup -n openshift-adp -l app=ibu-cert-test --ignore-not-found=true 2>/dev/null || true
	@oc delete restore -n openshift-adp -l app=ibu-cert-test --ignore-not-found=true 2>/dev/null || true
	@oc delete certificate ibu-test-cert -n default --ignore-not-found=true 2>/dev/null || true
	@oc delete secret ibu-test-cert-tls -n default --ignore-not-found=true 2>/dev/null || true
	@oc delete dataprotectionapplication velero -n openshift-adp --ignore-not-found=true 2>/dev/null || true
	@oc delete secret cloud-credentials -n openshift-adp --ignore-not-found=true 2>/dev/null || true
	@oc delete subscription redhat-oadp-operator -n openshift-adp --ignore-not-found=true 2>/dev/null || true
	@oc delete csv -n openshift-adp -l operators.coreos.com/redhat-oadp-operator.openshift-adp --ignore-not-found=true 2>/dev/null || true
	@oc delete namespace openshift-adp --ignore-not-found=true 2>/dev/null || true
	@oc delete namespace minio --ignore-not-found=true 2>/dev/null || true
	@rm -rf /tmp/ibu-cert-state 2>/dev/null || true
	@echo "$(GREEN)IBU test resources cleaned.$(RESET)"

# ────────────────────────────────────────────────────────────────────────────────
# Cleanup
# ────────────────────────────────────────────────────────────────────────────────

delete-certificate: ## Delete a specific certificate (CERT=name NS=namespace)
	@if [ -z "$(CERT)" ] || [ -z "$(NS)" ]; then \
	  echo "$(YELLOW)Usage: make delete-certificate CERT=<name> NS=<namespace>$(RESET)"; \
	  echo "$(DIM)Example: make delete-certificate CERT=test-cert NS=default$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(YELLOW)Deleting certificate $(CERT) in namespace $(NS)...$(RESET)"
	@SECRET=$$($(KUBE_CLI) get certificate "$(CERT)" -n "$(NS)" -o jsonpath='{.spec.secretName}' 2>/dev/null || echo ""); \
	$(KUBE_CLI) delete certificate "$(CERT)" -n "$(NS)" --ignore-not-found=true; \
	if [ -n "$$SECRET" ]; then \
	  $(KUBE_CLI) delete secret "$$SECRET" -n "$(NS)" --ignore-not-found=true; \
	fi
	@echo "$(GREEN)Certificate $(CERT) deleted.$(RESET)"

delete-issuer: ## Delete a specific ClusterIssuer (ISSUER=name)
	@if [ -z "$(ISSUER)" ]; then \
	  echo "$(YELLOW)Usage: make delete-issuer ISSUER=<name>$(RESET)"; \
	  echo "$(DIM)Example: make delete-issuer ISSUER=pebble-issuer$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(YELLOW)Deleting ClusterIssuer $(ISSUER)...$(RESET)"
	@$(KUBE_CLI) delete clusterissuer "$(ISSUER)" --ignore-not-found=true
	@echo "$(GREEN)ClusterIssuer $(ISSUER) deleted.$(RESET)"

clean-certs: ## Clean up certificates, orders, and challenges
	@echo "$(BOLD)$(YELLOW)Cleaning up certificates...$(RESET)"
	@$(KUBE_CLI) delete certificates --all -n default --ignore-not-found=true
	@$(KUBE_CLI) delete certificaterequests --all -n default --ignore-not-found=true
	@$(KUBE_CLI) delete orders --all -n default --ignore-not-found=true
	@$(KUBE_CLI) delete challenges --all -n default --ignore-not-found=true
	@$(KUBE_CLI) delete secrets wildcard-test-tls test-cert-simple-tls test-cert-app-tls test-cert-api-tls test-cert-http01-tls -n default --ignore-not-found=true
	@echo "$(GREEN)Certificates cleaned.$(RESET)"

clean-pebble: ## Clean up Pebble ACME test server
	@echo "$(BOLD)$(YELLOW)Cleaning up Pebble...$(RESET)"
	@$(KUBE_CLI) delete namespace pebble --ignore-not-found=true --timeout=60s --wait=false
	@$(KUBE_CLI) delete secret pebble-dns01-issuer-account-key pebble-issuer-account-key -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Pebble cleaned.$(RESET)"

clean-fake-dns: ## Clean up fake DNS API
	@echo "$(BOLD)$(YELLOW)Cleaning up fake DNS...$(RESET)"
	@$(KUBE_CLI) delete namespace fake-dns --ignore-not-found=true --timeout=60s --wait=false
	@$(KUBE_CLI) patch dns.operator.openshift.io/default --type=merge -p '{"spec":{"servers":null}}' 2>/dev/null || true
	@echo "$(GREEN)Fake DNS cleaned.$(RESET)"

clean-acmedns: ## Clean up acme-dns local DNS server
	@echo "$(BOLD)$(YELLOW)Cleaning up acme-dns...$(RESET)"
	@$(KUBE_CLI) delete namespace acme-dns --ignore-not-found=true --timeout=60s --wait=false
	@echo "$(GREEN)acme-dns cleaned.$(RESET)"

clean-challtestsrv: ## Clean up Pebble challenge test server
	@echo "$(BOLD)$(YELLOW)Cleaning up pebble-challtestsrv...$(RESET)"
	@$(KUBE_CLI) delete deployment pebble-challtestsrv -n pebble --ignore-not-found=true
	@$(KUBE_CLI) delete service pebble-challtestsrv -n pebble --ignore-not-found=true
	@$(KUBE_CLI) delete configmap pebble-challtestsrv-config -n pebble --ignore-not-found=true
	@echo "$(GREEN)pebble-challtestsrv cleaned.$(RESET)"

clean-dns-config: ## Restore DNS configuration
	@echo "Restoring DNS configuration..."
	@if [ "$(CLUSTER_TYPE)" = "openshift" ]; then \
		$(KUBE_CLI) patch dns.operator.openshift.io/default --type=json -p='[{"op": "remove", "path": "/spec/servers"}]' 2>/dev/null || true; \
	fi
	@echo "DNS configuration restored."

clean-issuers: ## Clean up ClusterIssuers (ACME/Pebble)
	@echo "$(BOLD)$(YELLOW)Cleaning up ClusterIssuers...$(RESET)"
	@$(KUBE_CLI) delete clusterissuer pebble-issuer pebble-dns01-issuer --ignore-not-found=true
	@$(KUBE_CLI) delete secret rfc2136-credentials -n default --ignore-not-found=true
	@echo "$(GREEN)ClusterIssuers cleaned.$(RESET)"

clean-selfsigned: ## Clean up self-signed CA chain
	@echo "$(BOLD)$(YELLOW)Cleaning up self-signed CA resources...$(RESET)"
	@$(KUBE_CLI) delete certificate test-cert-selfsigned -n default --ignore-not-found=true
	@$(KUBE_CLI) delete secret test-cert-selfsigned-tls -n default --ignore-not-found=true
	@$(KUBE_CLI) delete clusterissuer selfsigned-ca-issuer selfsigned-issuer --ignore-not-found=true
	@$(KUBE_CLI) delete certificate root-ca -n cert-manager --ignore-not-found=true
	@$(KUBE_CLI) delete secret root-ca-secret -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Self-signed CA resources cleaned.$(RESET)"

clean-cert-renewal: ## Clean up renewal test certificate
	@echo "$(BOLD)$(YELLOW)Cleaning up renewal test resources...$(RESET)"
	@$(KUBE_CLI) delete certificate -l app=cert-renewal-test --all-namespaces --ignore-not-found=true
	@$(KUBE_CLI) delete secret renewal-test-tls -n $${CERT_NAMESPACE:-default} --ignore-not-found=true
	@echo "$(GREEN)Renewal test resources cleaned.$(RESET)"

clean-ingress-test: ## Clean up ingress TLS test resources
	@echo "$(BOLD)$(YELLOW)Cleaning up ingress TLS test resources...$(RESET)"
	@$(KUBE_CLI) delete namespace ingress-tls-test --ignore-not-found=true --timeout=60s --wait=false
	@echo "$(GREEN)Ingress TLS test resources cleaned.$(RESET)"

clean-monitoring: ## Clean up cert-manager monitoring resources (alias: uninstall-monitoring)
	@echo "$(BOLD)$(YELLOW)Cleaning up monitoring resources...$(RESET)"
	@$(KUBE_CLI) delete servicemonitor/cert-manager prometheusrule/cert-manager-alerts -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Monitoring resources cleaned.$(RESET)"

uninstall-monitoring: clean-monitoring ## Uninstall cert-manager ServiceMonitor and PrometheusRule (alias of clean-monitoring)

clean-temp: ## Clean up temporary files
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name ".*.swp" -delete
	@echo "Temp files cleaned."

clean: clean-certs clean-issuers clean-selfsigned clean-monitoring clean-pebble clean-fake-dns clean-acmedns clean-challtestsrv clean-dns-config ## Clean everything except cert-manager-operator
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║                  Cleanup Complete!                          ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo ""
	@echo "cert-manager-operator is still installed."
	@echo "To test again, run: make test-dns01"

uninstall-cert-manager-operator: ## Uninstall cert-manager Operator (WARNING!)
	@echo "$(RED)$(BOLD)WARNING: This will uninstall cert-manager-operator!$(RESET)"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@echo "Uninstalling cert-manager-operator..."
	@oc delete subscription cert-manager-operator -n openshift-cert-manager-operator --ignore-not-found=true
	@oc delete csv -n openshift-cert-manager-operator -l operators.coreos.com/cert-manager-operator.openshift-cert-manager-operator --ignore-not-found=true
	@oc delete namespace openshift-cert-manager-operator --ignore-not-found=true
	@echo "$(GREEN)cert-manager-operator uninstalled.$(RESET)"

uninstall-all: clean clean-ibu uninstall-cert-manager-operator ## Full teardown of all components (WARNING!)
