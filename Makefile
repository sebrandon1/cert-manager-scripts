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
        install-fake-dns install-all install-monitoring create-issuer create-dns01-issuer \
        create-selfsigned-issuer create-certs create-apiserver-cert verify-apiserver-cert \
        test-all test-dns01 quick-http-test quick-dns-test quick-selfsigned-test \
        test-cert verify-cert \
        troubleshoot check-cert check-issuer check-network check-network-stack check-workload-partitioning \
        diagnose-http01 diagnose-dns01 clean clean-certs clean-pebble clean-fake-dns \
        clean-dns-config clean-issuers clean-selfsigned clean-monitoring clean-temp \
        uninstall-cert-manager-operator \
        install-minio install-oadp install-ibu-prereqs capture-cert-state \
        test-ibu-certs test-ibu-preserved test-ibu-both quick-ibu-test clean-ibu

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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(create-|test-cert|verify-)"
	@echo ""
	@echo "$(YELLOW)Quick Tests:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(quick-|test-all|test-dns01)"
	@echo ""
	@echo "$(YELLOW)Troubleshooting:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(troubleshoot|diagnose|check-cert|check-issuer)"
	@echo ""
	@echo "$(YELLOW)IBU Testing:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(ibu|minio|oadp)"
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

quick-selfsigned-test: install-cert-manager-operator create-selfsigned-issuer ## Quick end-to-end self-signed CA test
	@echo ""
	@echo "$(BOLD)$(BLUE)Quick Self-Signed CA Test Running...$(RESET)"
	@echo ""
	@CLUSTER_DOMAIN=$$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "apps-crc.testing"); \
	ISSUER_NAME=$$(echo "$${CA_ISSUER_NAME:-selfsigned-ca-issuer}"); \
	printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: test-cert-selfsigned\n  namespace: default\nspec:\n  secretName: test-cert-selfsigned-tls\n  issuerRef:\n    name: '"$$ISSUER_NAME"'\n    kind: ClusterIssuer\n  dnsNames:\n  - test.'"$$CLUSTER_DOMAIN"'\n  - "*.'"$$CLUSTER_DOMAIN"'"\n' | oc apply -f -
	@echo ""
	@echo "Waiting for certificate (timeout: 2 minutes)..."
	@timeout=120; elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if oc get certificate test-cert-selfsigned -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "$(GREEN)Certificate issued successfully!$(RESET)"; \
			break; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then echo "  Still waiting... ($$elapsed seconds)"; fi; \
		sleep 2; elapsed=$$((elapsed + 2)); \
	done
	@echo ""
	@echo "Quick self-signed CA test complete! Run 'make clean-selfsigned' to clean up."

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

clean-issuers: ## Clean up ClusterIssuers (ACME/Pebble)
	@echo "$(BOLD)$(YELLOW)Cleaning up ClusterIssuers...$(RESET)"
	@oc delete clusterissuer pebble-issuer pebble-dns01-issuer --ignore-not-found=true
	@oc delete secret rfc2136-credentials -n default --ignore-not-found=true
	@echo "$(GREEN)ClusterIssuers cleaned.$(RESET)"

clean-selfsigned: ## Clean up self-signed CA chain
	@echo "$(BOLD)$(YELLOW)Cleaning up self-signed CA resources...$(RESET)"
	@oc delete certificate test-cert-selfsigned -n default --ignore-not-found=true
	@oc delete secret test-cert-selfsigned-tls -n default --ignore-not-found=true
	@oc delete clusterissuer selfsigned-ca-issuer selfsigned-issuer --ignore-not-found=true
	@oc delete certificate root-ca -n cert-manager --ignore-not-found=true
	@oc delete secret root-ca-secret -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Self-signed CA resources cleaned.$(RESET)"

clean-monitoring: ## Clean up cert-manager monitoring resources
	@echo "$(BOLD)$(YELLOW)Cleaning up monitoring resources...$(RESET)"
	@oc delete servicemonitor/cert-manager prometheusrule/cert-manager-alerts -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)Monitoring resources cleaned.$(RESET)"

clean-temp: ## Clean up temporary files
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name ".*.swp" -delete
	@echo "Temp files cleaned."

clean: clean-certs clean-issuers clean-selfsigned clean-monitoring clean-pebble clean-fake-dns clean-dns-config ## Clean everything except cert-manager-operator
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
