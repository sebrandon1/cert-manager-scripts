#!/bin/bash

################################################################################
# Script: create-issuer.sh
# Description: Create a cert-manager ClusterIssuer pointing to Pebble ACME server
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/issuers"

export ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
export ACME_SERVER_URL="${ACME_SERVER_URL:-https://pebble.pebble.svc.cluster.local:14000/dir}"
export ACME_EMAIL="${ACME_EMAIL:-test@example.com}"
export INGRESS_CLASS="${INGRESS_CLASS:-openshift-default}"

check_pebble() {
	log_info "Checking if Pebble is available..."

	if ! oc get deployment -n pebble pebble &>/dev/null; then
		log_warn "Pebble ACME server not found."
		log_info "This issuer will point to: $ACME_SERVER_URL"
		log_warn "If using Pebble, install it first: make install-pebble"
		echo
		read -p "Continue anyway? (y/N): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			log_info "Cancelled."
			exit 0
		fi
	else
		log_info "Pebble ACME server is available."

		local ready_replicas=$(oc get deployment pebble -n pebble -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
		if [ "$ready_replicas" = "0" ]; then
			log_warn "Pebble deployment exists but no replicas are ready."
		else
			log_info "Pebble is ready with $ready_replicas replica(s)."
		fi
	fi
}

check_existing_issuer() {
	log_info "Checking for existing ClusterIssuer '$ISSUER_NAME'..."

	if oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_warn "ClusterIssuer '$ISSUER_NAME' already exists."

		local current_server=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.server}' 2>/dev/null || echo "unknown")
		log_debug "Current ACME server: $current_server"

		echo
		read -p "Overwrite existing issuer? (y/N): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			log_info "Keeping existing issuer."
			exit 0
		fi
	fi
}

display_configuration() {
	log_info "========================================"
	log_info "  ClusterIssuer Configuration"
	log_info "========================================"
	echo
	echo "Issuer Name:      $ISSUER_NAME"
	echo "ACME Server:      $ACME_SERVER_URL"
	echo "Email:            $ACME_EMAIL"
	echo "Ingress Class:    $INGRESS_CLASS"
	echo "Skip TLS Verify:  true (for Pebble self-signed certs)"
	echo
}

create_issuer() {
	log_info "Creating ClusterIssuer '$ISSUER_NAME'..."

	envsubst <"$YAML_DIR/pebble-clusterissuer.yaml" | oc apply -f -

	if [ $? -eq 0 ]; then
		log_info "ClusterIssuer created successfully."
	else
		log_error "Failed to create ClusterIssuer."
		exit 1
	fi
}

verify_issuer() {
	log_info "Waiting for ClusterIssuer to be ready..."

	local max_attempts=30
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		local ready=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

		if [ "$ready" = "True" ]; then
			log_info "ClusterIssuer is ready!"
			break
		fi

		attempt=$((attempt + 1))
		if [ $((attempt % 5)) -eq 0 ]; then
			echo -n " [${attempt}/${max_attempts}]"
		else
			echo -n "."
		fi
		sleep 2
	done
	echo

	if [ $attempt -eq $max_attempts ]; then
		log_warn "Timeout waiting for ClusterIssuer to be ready."
		log_info "Check status with: oc describe clusterissuer $ISSUER_NAME"
	fi

	echo
	log_info "ClusterIssuer status:"
	oc get clusterissuer "$ISSUER_NAME"
}

# Function to display next steps
display_next_steps() {
	echo
	log_info "========================================"
	log_info "  ClusterIssuer Created!"
	log_info "========================================"
	echo
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

	require_cmd oc envsubst
	require_cluster

	if ! oc get deployment -n cert-manager cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		log_info "  Run: make install-cert-manager-operator"
		exit 1
	fi

	log_info "Waiting for cert-manager webhook to be ready..."
	if ! oc wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager; then
		log_error "Timeout waiting for cert-manager webhook to be ready."
		log_info "  Check webhook status: oc get deployment cert-manager-webhook -n cert-manager"
		exit 1
	fi
	log_info "cert-manager webhook is ready."

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
