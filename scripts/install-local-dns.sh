#!/bin/bash

################################################################################
# Script: install-local-dns.sh
# Description: Install acme-dns for local DNS-01 challenge testing
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/acme-dns"

export ACMEDNS_NAMESPACE="${ACMEDNS_NAMESPACE:-acme-dns}"

install_acme_dns() {
	log_info "Installing acme-dns..."

	apply_yaml_template "$YAML_DIR/namespace.yaml" "Namespace"
	apply_yaml_template "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml_template "$YAML_DIR/service.yaml" "Service"

	log_info "Resources applied. Waiting for acme-dns to be ready..."
}

verify_installation() {
	log_info "Verifying acme-dns installation..."

	log_info "Checking pods..."
	oc get pods -n "$ACMEDNS_NAMESPACE"
	echo

	log_info "Checking service..."
	oc get service acme-dns -n "$ACMEDNS_NAMESPACE"
	echo

	log_info "Installation verification complete!"
}

display_next_steps() {
	local acmedns_api="http://acme-dns.${ACMEDNS_NAMESPACE}.svc.cluster.local:8080"
	local acmedns_dns="acme-dns.${ACMEDNS_NAMESPACE}.svc.cluster.local"

	print_header "acme-dns Installation Complete!"
	echo "acme-dns is now running!"
	echo
	echo "Next steps:"
	echo
	echo "1. Update Pebble to use acme-dns for validation:"
	echo "   oc delete namespace pebble"
	echo "   DNS_SERVER=${acmedns_dns}:53 PEBBLE_ALWAYS_VALID=1 make install-pebble"
	echo
	echo "2. Install cert-manager webhook for acme-dns:"
	echo "   See docs/dns01-setup.md for Helm-based webhook installation"
	echo
	echo "3. Create a DNS-01 ClusterIssuer:"
	echo "   make create-dns01-issuer"
	echo
	echo "4. Test with a wildcard certificate:"
	echo "   make test-cert"
	echo
	echo "acme-dns URLs:"
	echo "  - API: ${acmedns_api}"
	echo "  - DNS: ${acmedns_dns}:53"
	echo
	log_info "acme-dns provides a REST API for creating/updating DNS TXT records"
	log_info "cert-manager will use this API for DNS-01 challenges"
	echo
}

main() {
	print_header "Install Local DNS Server (acme-dns)"

	require_cmd oc envsubst
	require_cluster
	require_healthy_cluster

	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	if check_deployment_exists acme-dns "$ACMEDNS_NAMESPACE"; then
		log_info "acme-dns is already installed and running."
		log_info "Installation is idempotent - will verify components."
	else
		log_info "No existing installation found. Will proceed with fresh installation."
	fi

	install_acme_dns
	wait_for_resource "deployment/acme-dns" "$ACMEDNS_NAMESPACE" "300s"
	verify_installation
	display_next_steps
}

main
