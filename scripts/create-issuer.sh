#!/bin/bash

################################################################################
# Script: create-issuer.sh
# Description: Create a cert-manager ClusterIssuer pointing to Pebble ACME server
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

YAML_DIR="${SCRIPT_DIR}/../yaml/issuers"

export ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
export ACME_SERVER_URL="${ACME_SERVER_URL:-https://pebble.pebble.svc.cluster.local:14000/dir}"
export ACME_EMAIL="${ACME_EMAIL:-test@example.com}"
if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
	export INGRESS_CLASS="${INGRESS_CLASS:-openshift-default}"
else
	export INGRESS_CLASS="${INGRESS_CLASS:-}"
fi

check_pebble() {
	log_info "Checking if Pebble is available..."

	if ! "$KUBE_CLI" get deployment -n pebble pebble &>/dev/null; then
		log_warn "Pebble ACME server not found."
		log_info "This issuer will point to: $ACME_SERVER_URL"
		log_warn "If using Pebble, install it first: make install-pebble"
		echo
		if ! confirm "Continue anyway?"; then
			log_info "Cancelled."
			exit 0
		fi
	else
		log_info "Pebble ACME server is available."

		local ready_replicas
		ready_replicas=$("$KUBE_CLI" get deployment pebble -n pebble -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
		if [ "$ready_replicas" = "0" ]; then
			log_warn "Pebble deployment exists but no replicas are ready."
		else
			log_info "Pebble is ready with $ready_replicas replica(s)."
		fi
	fi
}

check_existing_issuer() {
	log_info "Checking for existing ClusterIssuer '$ISSUER_NAME'..."

	if "$KUBE_CLI" get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_warn "ClusterIssuer '$ISSUER_NAME' already exists."

		local current_server
		current_server=$("$KUBE_CLI" get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.server}' 2>/dev/null || echo "unknown")
		log_debug "Current ACME server: $current_server"

		echo
		if ! confirm "Overwrite existing issuer?"; then
			log_info "Keeping existing issuer."
			exit 0
		fi
	fi
}

display_configuration() {
	print_header "ClusterIssuer Configuration"
	echo "Issuer Name:      $ISSUER_NAME"
	echo "ACME Server:      $ACME_SERVER_URL"
	echo "Email:            $ACME_EMAIL"
	echo "Ingress Class:    $INGRESS_CLASS"
	echo "Skip TLS Verify:  true (for Pebble self-signed certs)"
	echo
}

create_issuer() {
	apply_yaml_template "$YAML_DIR/pebble-clusterissuer.yaml" "ClusterIssuer"
}

check_issuer_ready() {
	local ready
	ready=$("$KUBE_CLI" get clusterissuer "$ISSUER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
	[ "$ready" = "True" ]
}

verify_issuer() {
	log_info "Waiting for ClusterIssuer to be ready..."

	if wait_for_condition 30 2 check_issuer_ready; then
		log_success "ClusterIssuer is ready!"
	else
		log_warn "Timeout waiting for ClusterIssuer to be ready."
		log_info "Check status with: oc describe clusterissuer $ISSUER_NAME"
	fi

	echo
	log_info "ClusterIssuer status:"
	"$KUBE_CLI" get clusterissuer "$ISSUER_NAME"
}

# Function to display next steps
display_next_steps() {
	print_header "ClusterIssuer Created!"
	log_info "HTTP-01 Validation Flow:"
	echo
	echo "When you create a certificate:"
	echo
	echo "✅ cert-manager requests a certificate from Pebble"
	echo "✅ Pebble responds with a challenge token"
	echo "✅ cert-manager creates a temporary HTTP endpoint with the token"
	echo "✅ Pebble validates by fetching the token via HTTP"
	echo "✅ Certificate is issued upon successful validation"
	echo
	echo "Next steps:"
	echo
	echo "1. View ClusterIssuer details:"
	echo "   oc describe clusterissuer $ISSUER_NAME"
	echo
	echo "2. Create test certificates:"
	echo "   make create-certs"
	echo
	echo "3. Or create a certificate manually:"
	echo "   cat <<EOF | oc apply -f -"
	echo "   apiVersion: cert-manager.io/v1"
	echo "   kind: Certificate"
	echo "   metadata:"
	echo "     name: my-test-cert"
	echo "     namespace: default"
	echo "   spec:"
	echo "     secretName: my-test-cert-tls"
	echo "     issuerRef:"
	echo "       name: $ISSUER_NAME"
	echo "       kind: ClusterIssuer"
	echo "     dnsNames:"
	echo "     - test.example.com"
	echo "   EOF"
	echo
	echo "4. Monitor certificate requests:"
	echo "   oc get certificate -A"
	echo "   oc get order,challenge -A"
	echo
}

main() {
	print_header "Create cert-manager ClusterIssuer"

	require_cmd "$KUBE_CLI" envsubst
	require_cluster
	require_cert_manager

	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	display_configuration
	check_pebble
	check_existing_issuer
	create_issuer
	verify_issuer
	display_next_steps
}

main
