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
.PHONY: all help banner preflight lint install-cert-manager-operator install-pebble \
        install-fake-dns install-all create-issuer create-dns01-issuer create-certs \
        test-all test-dns01 quick-http-test quick-dns-test test-cert verify-cert \
        troubleshoot check-cert check-issuer check-network check-workload-partitioning \
        diagnose-http01 diagnose-dns01 clean clean-certs clean-pebble clean-fake-dns \
        clean-dns-config clean-issuers clean-temp uninstall-cert-manager-operator

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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(preflight|lint|check-network|check-workload)"
	@echo ""
	@echo "$(YELLOW)Installation:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(install-)"
	@echo ""
	@echo "$(YELLOW)Issuers & Certificates:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(create-|test-cert|verify-cert)"
	@echo ""
	@echo "$(YELLOW)Quick Tests:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(quick-|test-all|test-dns01)"
	@echo ""
	@echo "$(YELLOW)Troubleshooting:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(troubleshoot|diagnose|check-cert|check-issuer)"
	@echo ""
	@echo "$(YELLOW)Cleanup:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(clean|uninstall)"
	@echo ""
	@echo "$(DIM)Usage: make <command>$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# Setup & Validation
# ────────────────────────────────────────────────────────────────────────────────

preflight: ## Check all dependencies and prerequisites
	@./scripts/preflight-check.sh
	@echo ""

lint: ## Check shell script formatting with shfmt and shellcheck
	@echo "$(BOLD)$(BLUE)Linting Bash scripts...$(RESET)"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "$(RED)shellcheck not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shellcheck$(RESET)"; \
	  echo "$(DIM)  Linux: apt-get install shellcheck or dnf install ShellCheck$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(DIM)  Running shellcheck...$(RESET)"
	@find . -name '*.sh' -type f -not -path './venv/*' | xargs shellcheck -e SC1091,SC2034,SC2086,SC2155,SC2046,SC2181,SC2126,SC2329 || (echo "$(RED)shellcheck failed!$(RESET)" && exit 1)
	@if ! command -v shfmt >/dev/null 2>&1; then \
	  echo "$(RED)shfmt not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shfmt$(RESET)"; \
	  echo "$(DIM)  Linux: go install mvdan.cc/sh/v3/cmd/shfmt@latest$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(DIM)  Running shfmt...$(RESET)"
	@shfmt -d scripts/ lib/ || (echo "$(RED)shfmt formatting check failed!$(RESET)" && echo "$(YELLOW)To fix: shfmt -w scripts/ lib/$(RESET)" && exit 1)
	@echo "$(GREEN)Bash linting passed!$(RESET)"

check-network: ## Check cluster network configuration (IPv4/IPv6/Dual-stack)
	@./scripts/check-cluster-network.sh

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

install-pebble: ## Install Pebble ACME test server
	@echo "$(BOLD)$(BLUE)Installing Pebble ACME test server...$(RESET)"
	@./scripts/install-pebble.sh
	@echo ""

install-fake-dns: ## Install fake DNS API for air-gapped DNS-01 testing
	@echo "$(BOLD)$(BLUE)Installing fake DNS API for air-gapped testing...$(RESET)"
	@./scripts/install-fake-dns.sh
	@echo ""

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

create-certs: ## Create test certificates (HTTP-01)
	@./scripts/create-test-certificates.sh

test-cert: ## Create a test wildcard certificate (DNS-01)
	@echo "Creating test wildcard certificate..."
	@printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: wildcard-test\n  namespace: default\nspec:\n  secretName: wildcard-test-tls\n  issuerRef:\n    name: pebble-dns01-issuer\n    kind: ClusterIssuer\n  dnsNames:\n  - "*.example.com"\n  - "example.com"\n' | oc apply -f -
	@echo "Certificate created. Run 'make verify-cert' to check status."

verify-cert: ## Verify certificate status
	@echo ""
	@echo "$(BOLD)Certificate Status$(RESET)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@oc get certificate wildcard-test -n default 2>/dev/null || echo "Certificate not found"
	@echo ""
	@echo "Orders:"
	@oc get order -n default 2>/dev/null || echo "No orders found"
	@echo ""
	@echo "Challenges:"
	@oc get challenge -n default 2>/dev/null || echo "No challenges found"
	@echo ""
	@if oc get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
		echo "$(GREEN)Certificate is READY!$(RESET)"; \
	else \
		echo "$(YELLOW)Certificate is still being issued...$(RESET)"; \
	fi

# ────────────────────────────────────────────────────────────────────────────────
# Quick Tests
# ────────────────────────────────────────────────────────────────────────────────

test-all: install-all create-issuer create-certs ## Complete HTTP-01 setup (install + issuer + certs)
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
	@echo "Reinstalling Pebble with fake DNS..."
	@oc delete namespace pebble --ignore-not-found=true
	@sleep 10
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 PEBBLE_ALWAYS_VALID=1 ./scripts/install-pebble.sh
	@echo ""
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

quick-http-test: install-cert-manager-operator ## Quick end-to-end HTTP-01 test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick HTTP-01 Test Running...$(RESET)"
	@echo ""
	@PEBBLE_ALWAYS_VALID=1 $(MAKE) install-pebble || true
	@$(MAKE) create-issuer || true
	@CLUSTER_DOMAIN=$$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "apps-crc.testing"); \
	printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: test-cert-http01\n  namespace: default\nspec:\n  secretName: test-cert-http01-tls\n  issuerRef:\n    name: pebble-issuer\n    kind: ClusterIssuer\n  dnsNames:\n  - test.'"$$CLUSTER_DOMAIN"'\n' | oc apply -f -
	@echo ""
	@echo "Waiting for certificate (timeout: 3 minutes)..."
	@timeout=180; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if oc get certificate test-cert-http01 -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			break; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done
	@echo ""
	@echo "Quick HTTP-01 test complete! Run 'make clean' to clean up."

quick-dns-test: test-dns01 test-cert ## Quick end-to-end DNS-01 test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick DNS-01 Test Running...$(RESET)"
	@echo ""
	@echo "Waiting for certificate (timeout: 5 minutes)..."
	@timeout=300; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if oc get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			break; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done
	@$(MAKE) verify-cert
	@echo ""
	@echo "Quick DNS-01 test complete! Run 'make clean' to clean up."

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

# ────────────────────────────────────────────────────────────────────────────────
# Cleanup
# ────────────────────────────────────────────────────────────────────────────────

clean-certs: ## Clean up certificates, orders, and challenges
	@echo "$(BOLD)$(YELLOW)Cleaning up certificates...$(RESET)"
	@oc delete certificates --all -n default --ignore-not-found=true
	@oc delete certificaterequests --all -n default --ignore-not-found=true
	@oc delete orders --all -n default --ignore-not-found=true
	@oc delete challenges --all -n default --ignore-not-found=true
	@oc delete secrets wildcard-test-tls test-cert-simple-tls test-cert-app-tls test-cert-api-tls test-cert-http01-tls -n default --ignore-not-found=true
	@echo "$(GREEN)Certificates cleaned.$(RESET)"

clean-pebble: ## Clean up Pebble ACME test server
	@echo "$(BOLD)$(YELLOW)Cleaning up Pebble...$(RESET)"
	@oc delete namespace pebble --ignore-not-found=true
	@oc delete secret pebble-dns01-issuer-account-key pebble-issuer-account-key -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Pebble cleaned.$(RESET)"

clean-fake-dns: ## Clean up fake DNS API
	@echo "$(BOLD)$(YELLOW)Cleaning up fake DNS...$(RESET)"
	@oc delete namespace fake-dns --ignore-not-found=true
	@echo "$(GREEN)Fake DNS cleaned.$(RESET)"

clean-dns-config: ## Restore DNS configuration
	@echo "Restoring DNS configuration..."
	@oc patch dns.operator.openshift.io/default --type=json -p='[{"op": "remove", "path": "/spec/servers"}]' 2>/dev/null || true
	@echo "DNS configuration restored."

clean-issuers: ## Clean up ClusterIssuers
	@echo "$(BOLD)$(YELLOW)Cleaning up ClusterIssuers...$(RESET)"
	@oc delete clusterissuer pebble-issuer pebble-dns01-issuer --ignore-not-found=true
	@oc delete secret rfc2136-credentials -n default --ignore-not-found=true
	@echo "$(GREEN)ClusterIssuers cleaned.$(RESET)"

clean-temp: ## Clean up temporary files
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name ".*.swp" -delete
	@echo "Temp files cleaned."

clean: clean-certs clean-issuers clean-pebble clean-fake-dns clean-dns-config ## Clean everything except cert-manager-operator
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
