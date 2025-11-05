.PHONY: help check-network install-cert-manager-operator install-pebble install-fake-dns install-all create-issuer create-dns01-issuer create-certs test-all test-dns01 quick-test test-cert verify-cert clean clean-certs clean-pebble clean-fake-dns clean-dns-config clean-issuers clean-temp uninstall-cert-manager-operator

# Default target
help:
	@echo "cert-manager-scripts Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  check-network                   - Check cluster network configuration (IPv4/IPv6/Dual-stack)"
	@echo "  install-cert-manager-operator   - Install cert-manager Operator for Red Hat OpenShift"
	@echo "  install-pebble                  - Install Pebble ACME test server"
	@echo "  install-fake-dns                - Install fake DNS API for air-gapped DNS-01 testing"
	@echo "  install-all                     - Install cert-manager-operator and Pebble"
	@echo "  create-issuer                   - Create ClusterIssuer pointing to Pebble (HTTP-01)"
	@echo "  create-dns01-issuer             - Create ClusterIssuer pointing to Pebble (DNS-01)"
	@echo "  create-certs                    - Create test certificates (HTTP-01)"
	@echo "  test-all                        - Complete HTTP-01 setup"
	@echo "  test-dns01                      - Complete DNS-01 setup (air-gapped)"
	@echo "  quick-test                      - Quick end-to-end DNS-01 test (setup + test + verify)"
	@echo "  test-cert                       - Create a test wildcard certificate"
	@echo "  verify-cert                     - Verify certificate status"
	@echo "  clean                           - Clean up all resources (keeps cert-manager-operator)"
	@echo "  clean-certs                     - Clean up certificates and challenges only"
	@echo "  clean-pebble                    - Clean up Pebble only"
	@echo "  clean-fake-dns                  - Clean up fake DNS only"
	@echo "  clean-issuers                   - Clean up ClusterIssuers only"
	@echo "  clean-temp                      - Clean up temporary files"
	@echo "  uninstall-cert-manager-operator - Uninstall cert-manager Operator (WARNING!)"
	@echo "  help                            - Show this help message"
	@echo ""

# Check cluster network configuration
check-network:
	@./check-cluster-network.sh

# Install cert-manager-operator
install-cert-manager-operator:
	@echo "Installing cert-manager Operator for Red Hat OpenShift..."
	@./install-cert-manager-operator.sh

# Install Pebble ACME test server
install-pebble:
	@echo "Installing Pebble ACME test server..."
	@./install-pebble.sh

# Install fake DNS API
install-fake-dns:
	@echo "Installing fake DNS API for air-gapped testing..."
	@./install-fake-dns.sh

# Install everything
install-all: install-cert-manager-operator install-pebble
	@echo ""
	@echo "All components installed successfully!"

# Create ClusterIssuer pointing to Pebble (HTTP-01)
create-issuer:
	@./create-issuer.sh

# Create ClusterIssuer pointing to Pebble (DNS-01)
create-dns01-issuer:
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 ./create-dns01-issuer.sh

# Create test certificates
create-certs:
	@./create-test-certificates.sh

# Complete test setup: install everything + create issuer + create certificates
test-all: install-all create-issuer create-certs
	@echo ""
	@echo "========================================" 
	@echo "  Complete Test Environment Ready!"
	@echo "========================================"
	@echo ""
	@echo "You can now test certificate issuance with:"
	@echo "  oc get certificate -A"
	@echo "  oc get order,challenge -A"

# Complete DNS-01 test setup (air-gapped)
test-dns01: install-fake-dns
	@echo "Reinstalling Pebble with fake DNS..."
	@oc delete namespace pebble --ignore-not-found=true
	@sleep 10
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 PEBBLE_ALWAYS_VALID=1 ./install-pebble.sh
	@echo ""
	@echo "Creating DNS-01 issuer..."
	@DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 ./create-dns01-issuer.sh
	@echo ""
	@echo "========================================"
	@echo "  DNS-01 Environment Ready!"
	@echo "========================================"
	@echo ""
	@echo "Test with a wildcard certificate:"
	@echo "  oc apply -f - <<EOF"
	@echo "  apiVersion: cert-manager.io/v1"
	@echo "  kind: Certificate"
	@echo "  metadata:"
	@echo "    name: wildcard-test"
	@echo "    namespace: default"
	@echo "  spec:"
	@echo "    secretName: wildcard-test-tls"
	@echo "    issuerRef:"
	@echo "      name: pebble-dns01-issuer"
	@echo "      kind: ClusterIssuer"
	@echo "    dnsNames:"
	@echo "    - '*.example.com'"
	@echo "    - 'example.com'"
	@echo "  EOF"
	@echo ""
	@echo "Monitor progress:"
	@echo "  watch oc get certificate -n default"

# Quick end-to-end test
quick-test: test-dns01 test-cert
	@echo ""
	@echo "========================================"
	@echo "  Quick Test Running..."
	@echo "========================================"
	@echo ""
	@echo "Waiting for certificate to be issued (timeout: 5 minutes)..."
	@timeout=300; \
	elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if oc get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
			echo "✅ Certificate issued successfully!"; \
			break; \
		fi; \
		if [ $$((elapsed % 10)) -eq 0 ]; then \
			echo "  ⏳ Still waiting... ($$elapsed seconds elapsed)"; \
		fi; \
		sleep 2; \
		elapsed=$$((elapsed + 2)); \
	done
	@echo ""
	@$(MAKE) verify-cert
	@echo ""
	@echo "Quick test complete! Run 'make clean' to clean up."

# Create a test wildcard certificate
test-cert:
	@echo "Creating test wildcard certificate..."
	@printf 'apiVersion: cert-manager.io/v1\nkind: Certificate\nmetadata:\n  name: wildcard-test\n  namespace: default\nspec:\n  secretName: wildcard-test-tls\n  issuerRef:\n    name: pebble-dns01-issuer\n    kind: ClusterIssuer\n  dnsNames:\n  - "*.example.com"\n  - "example.com"\n' | oc apply -f -
	@echo "Certificate created. Run 'make verify-cert' to check status."

# Verify certificate status
verify-cert:
	@echo ""
	@echo "========================================"
	@echo "  Certificate Status"
	@echo "========================================"
	@echo ""
	@oc get certificate wildcard-test -n default 2>/dev/null || echo "Certificate not found"
	@echo ""
	@echo "Orders:"
	@oc get order -n default 2>/dev/null || echo "No orders found"
	@echo ""
	@echo "Challenges:"
	@oc get challenge -n default 2>/dev/null || echo "No challenges found"
	@echo ""
	@if oc get certificate wildcard-test -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then \
		echo "✅ Certificate is READY!"; \
		echo ""; \
		echo "View certificate details:"; \
		echo "  oc get secret wildcard-test-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout"; \
	else \
		echo "⏳ Certificate is still being issued..."; \
		echo ""; \
		echo "Monitor progress with:"; \
		echo "  watch oc get certificate -n default"; \
		echo ""; \
		echo "Check challenges:"; \
		echo "  oc get challenge -n default"; \
		echo ""; \
		echo "Check logs:"; \
		echo "  oc logs -n cert-manager deployment/cert-manager --tail=50"; \
	fi

# Clean up certificates, orders, and challenges
clean-certs:
	@echo "Cleaning up certificates, orders, and challenges..."
	@oc delete certificates --all -n default --ignore-not-found=true
	@oc delete certificaterequests --all -n default --ignore-not-found=true
	@oc delete orders --all -n default --ignore-not-found=true
	@oc delete challenges --all -n default --ignore-not-found=true
	@oc delete secrets wildcard-test-tls test-cert-simple-tls test-cert-app-tls test-cert-api-tls -n default --ignore-not-found=true
	@echo "Certificates cleaned."

# Clean up Pebble
clean-pebble:
	@echo "Cleaning up Pebble..."
	@oc delete namespace pebble --ignore-not-found=true
	@oc delete secret pebble-dns01-issuer-account-key pebble-issuer-account-key -n cert-manager --ignore-not-found=true
	@echo "Pebble cleaned."

# Clean up fake DNS
clean-fake-dns:
	@echo "Cleaning up fake DNS..."
	@oc delete namespace fake-dns --ignore-not-found=true
	@echo "Fake DNS cleaned."

# Clean up DNS configuration
clean-dns-config:
	@echo "Restoring DNS configuration..."
	@oc patch dns.operator.openshift.io/default --type=json -p='[{"op": "remove", "path": "/spec/servers"}]' 2>/dev/null || true
	@echo "DNS configuration restored."

# Clean up ClusterIssuers
clean-issuers:
	@echo "Cleaning up ClusterIssuers..."
	@oc delete clusterissuer pebble-issuer pebble-dns01-issuer --ignore-not-found=true
	@oc delete secret rfc2136-credentials -n default --ignore-not-found=true
	@echo "ClusterIssuers cleaned."

# Clean everything except cert-manager-operator
clean: clean-certs clean-issuers clean-pebble clean-fake-dns clean-dns-config
	@echo ""
	@echo "========================================"
	@echo "  Cleanup Complete!"
	@echo "========================================"
	@echo ""
	@echo "cert-manager-operator is still installed."
	@echo "To test again, run: make test-dns01"

# Clean temporary files
clean-temp:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name ".*.swp" -delete
	@echo "Temp files cleaned."

# Uninstall cert-manager-operator (use with caution)
uninstall-cert-manager-operator:
	@echo "WARNING: This will uninstall cert-manager-operator!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@echo "Uninstalling cert-manager-operator..."
	@oc delete subscription cert-manager-operator -n openshift-cert-manager-operator --ignore-not-found=true
	@oc delete csv -n openshift-cert-manager-operator -l operators.coreos.com/cert-manager-operator.openshift-cert-manager-operator --ignore-not-found=true
	@oc delete namespace openshift-cert-manager-operator --ignore-not-found=true
	@echo "cert-manager-operator uninstalled."
