#!/bin/bash

################################################################################
# Script: install-pebble.sh
# Description: Install Pebble ACME test server for local cert-manager testing
# Reference: https://github.com/letsencrypt/pebble
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/pebble"

export PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"
export DNS_SERVER="${DNS_SERVER:-8.8.8.8:53}"
export PEBBLE_ALWAYS_VALID="${PEBBLE_ALWAYS_VALID:-0}"

install_pebble() {
	log_info "Installing Pebble ACME test server..."

	apply_yaml_template "$YAML_DIR/namespace.yaml" "Namespace"
	apply_yaml_template "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml_template "$YAML_DIR/service.yaml" "Service"
	apply_yaml_template "$YAML_DIR/route.yaml" "Route"

	log_info "Resources applied. Waiting for Pebble to be ready..."
}

verify_installation() {
	log_info "Verifying Pebble installation..."

	log_info "Checking pod status..."
	oc get pods -n "$PEBBLE_NAMESPACE"
	echo

	log_info "Checking service..."
	oc get service pebble -n "$PEBBLE_NAMESPACE"
	echo

	log_info "Checking route..."
	oc get route pebble-acme -n "$PEBBLE_NAMESPACE"
	echo

	local route_host=$(oc get route pebble-acme -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

	if [ -n "$route_host" ]; then
		log_info "Pebble ACME directory URL: https://${route_host}/dir"
	fi

	local service_url="https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:14000/dir"
	log_info "Pebble internal URL: ${service_url}"

	log_info "Installation verification complete!"
}

display_configuration() {
	echo
	log_info "========================================"
	log_info "  Pebble Configuration"
	log_info "========================================"
	echo
	echo "Namespace:           $PEBBLE_NAMESPACE"
	echo "DNS Server:          $DNS_SERVER"
	echo "Always Valid:        $PEBBLE_ALWAYS_VALID"
	echo

	if [ "$PEBBLE_ALWAYS_VALID" = "1" ]; then
		log_info "PEBBLE_ALWAYS_VALID=1: All challenges will automatically succeed."
		log_info "This is useful for testing without proper DNS/HTTP challenge setup."
	else
		log_info "PEBBLE_ALWAYS_VALID=0: Challenges must be properly configured."
		log_info "You'll need proper DNS records or HTTP-01 challenge routes."
	fi
	echo
}

display_next_steps() {
	local route_host=$(oc get route pebble-acme -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
	local service_url="https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:14000/dir"

	echo
	log_info "========================================"
	log_info "  Installation Complete!"
	log_info "========================================"
	echo
	echo "Pebble ACME server is now running!"
	echo
	echo "Next steps:"
	echo
	echo "1. Get Pebble's root CA certificate (for cert-manager to trust):"
	echo "   oc run --rm -i --tty pebble-ca-fetch --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0"
	echo
	echo "   Or save it to a file:"
	echo "   oc run --rm -i pebble-ca-fetch --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0 > pebble-ca.crt"
	echo
	echo "2. Configure a cert-manager ClusterIssuer pointing to Pebble:"
	echo "   ACME Server: ${service_url}"
	if [ -n "$route_host" ]; then
		echo "   External URL: https://${route_host}/dir"
	fi
	echo
	echo "   Note: Use 'skipTLSVerify: true' in your ClusterIssuer since Pebble uses self-signed certs"
	echo
	echo "3. Pebble URLs:"
	echo "   - ACME Directory: ${service_url}"
	echo "   - Management API: https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000"
	echo "   - Root CA: https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0"
	echo
	echo "4. View Pebble logs:"
	echo "   oc logs -n $PEBBLE_NAMESPACE deployment/pebble -f"
	echo
	echo "5. Test ACME directory (from inside cluster):"
	echo "   oc run --rm -i --tty curl-test --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k ${service_url}"
	echo

	if [ "$PEBBLE_ALWAYS_VALID" = "1" ]; then
		log_info "Remember: PEBBLE_ALWAYS_VALID=1 means all challenges auto-succeed."
		log_info "Great for initial testing, but doesn't validate actual DNS/HTTP setup."
	fi

	echo
	log_info "For more information about Pebble, visit:"
	log_info "https://github.com/letsencrypt/pebble"
	echo
}

main() {
	print_header "Pebble ACME Test Server Installation"

	require_cmd oc envsubst
	require_cluster

	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	display_configuration

	if check_deployment_exists pebble "$PEBBLE_NAMESPACE"; then
		log_info "Pebble is already installed and healthy."
		log_info "Installation is idempotent - will verify and ensure components are ready."
	else
		log_info "No existing installation found. Will proceed with fresh installation."
	fi

	install_pebble
	wait_for_resource "deployment/pebble" "$PEBBLE_NAMESPACE" "600s"
	verify_installation
	display_next_steps
}

main
