#!/bin/bash

################################################################################
# Script: create-test-certificates.sh
# Description: Create test certificates using cert-manager
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/certificates"

# Configuration (exported for envsubst)
export ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
export CERT_NAMESPACE="${CERT_NAMESPACE:-default}"

# Function to check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	require_cmd "$KUBE_CLI" envsubst
	require_cluster

	# Check if cert-manager is installed
	if ! "$KUBE_CLI" get deployment -n cert-manager cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		log_info "  Run: make install-cert-manager-operator"
		exit 1
	fi

	# Check if issuer exists
	if ! "$KUBE_CLI" get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_error "ClusterIssuer '$ISSUER_NAME' not found."
		log_info "  Create an issuer first: make create-issuer"
		exit 1
	fi

	# Check if namespace exists
	if ! "$KUBE_CLI" get namespace "$CERT_NAMESPACE" &>/dev/null; then
		log_warn "Namespace '$CERT_NAMESPACE' does not exist."
		if confirm "Create namespace '$CERT_NAMESPACE'?"; then
			"$KUBE_CLI" create namespace "$CERT_NAMESPACE"
			log_info "Namespace '$CERT_NAMESPACE' created."
		else
			log_error "Cannot create certificates without target namespace."
			exit 1
		fi
	fi

	log_info "Prerequisites check passed."
}

# Function to create a certificate
create_certificate() {
	local cert_name=$1
	local dns_name=$2
	local description=$3

	export CERT_NAME="$cert_name"
	export CERT_SECRET_NAME="${cert_name}-tls"
	export CERT_COMMON_NAME="$dns_name"
	export CERT_DNS_NAME="$dns_name"

	log_info "Creating certificate: $cert_name ($description)..."

	# Check if certificate already exists
	if "$KUBE_CLI" get certificate "$cert_name" -n "$CERT_NAMESPACE" &>/dev/null; then
		log_warn "Certificate '$cert_name' already exists in namespace '$CERT_NAMESPACE'."
		return 0
	fi

	apply_yaml_template "$YAML_DIR/test-certificate.yaml" "Certificate"
}

# Function to create multiple test certificates
create_test_certificates() {
	log_info "Creating test certificates in namespace '$CERT_NAMESPACE'..."
	echo

	# Certificate 1: Simple test certificate
	create_certificate \
		"test-cert-simple" \
		"test.example.com" \
		"Simple test certificate"

	# Certificate 2: Application certificate
	create_certificate \
		"test-cert-app" \
		"myapp.example.com" \
		"Application certificate"

	# Certificate 3: API certificate
	create_certificate \
		"test-cert-api" \
		"api.example.com" \
		"API certificate"

	echo
	log_info "All test certificates created."
}

# Function to show HTTP-01 validation flow
show_http01_flow() {
	print_header "HTTP-01 Validation Flow"
	echo "✅ cert-manager requests a certificate from Pebble"
	echo "✅ Pebble responds with a challenge token"
	echo "✅ cert-manager creates a temporary HTTP endpoint with the token"
	echo "✅ Pebble validates by fetching the token via HTTP"
	echo "✅ Certificate is issued upon successful validation"
	echo
}

check_test_certs_ready() {
	for cert in test-cert-simple test-cert-app test-cert-api; do
		if "$KUBE_CLI" get certificate "$cert" -n "$CERT_NAMESPACE" &>/dev/null; then
			local ready
			ready=$("$KUBE_CLI" get certificate "$cert" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' || echo "False")
			[ "$ready" != "True" ] && return 1
		fi
	done
	return 0
}

wait_for_certificates() {
	log_info "Waiting for certificates to be issued..."
	show_http01_flow

	if wait_for_condition 30 2 check_test_certs_ready; then
		log_success "All certificates are ready!"
	else
		log_warn "Timeout waiting for all certificates to be ready."
		log_info "This is normal if using PEBBLE_ALWAYS_VALID=0 without proper DNS/HTTP setup."
		log_info "Check certificate status below for details."
	fi
}

# Function to display certificate status
display_certificate_status() {
	print_header "Certificate Status"

	log_info "Certificates:"
	"$KUBE_CLI" get certificate -n "$CERT_NAMESPACE" 2>/dev/null || echo "No certificates found"

	echo
	log_info "Certificate Requests:"
	"$KUBE_CLI" get certificaterequest -n "$CERT_NAMESPACE" 2>/dev/null || echo "No certificate requests found"

	echo
	log_info "ACME Orders:"
	"$KUBE_CLI" get order -n "$CERT_NAMESPACE" 2>/dev/null || echo "No orders found"

	echo
	log_info "ACME Challenges:"
	"$KUBE_CLI" get challenge -n "$CERT_NAMESPACE" 2>/dev/null || echo "No challenges found"
}

# Function to display next steps
display_next_steps() {
	print_header "Next Steps"
	echo "1. Check certificate details:"
	echo "   oc describe certificate test-cert-simple -n $CERT_NAMESPACE"
	echo
	echo "2. View certificate secret:"
	echo "   oc get secret test-cert-simple-tls -n $CERT_NAMESPACE -o yaml"
	echo
	echo "3. Decode certificate:"
	echo "   oc get secret test-cert-simple-tls -n $CERT_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout"
	echo
	echo "4. Monitor all cert-manager resources:"
	echo "   watch oc get certificate -n $CERT_NAMESPACE"
	echo
	echo "5. Check cert-manager logs if issues occur:"
	echo "   oc logs -n cert-manager deployment/cert-manager -f"
	echo

	# Check if certificates failed
	local failed_certs
	failed_certs=$("$KUBE_CLI" get certificate -n "$CERT_NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | .metadata.name' | wc -l | tr -d ' ')

	if [ "$failed_certs" -gt 0 ]; then
		echo
		log_warn "Some certificates are not ready. Common reasons:"
		echo "  - Using PEBBLE_ALWAYS_VALID=0 without proper DNS/HTTP routes"
		echo "  - Challenge validation failing"
		echo "  - Network connectivity issues"
		echo
		echo "To debug, describe failed certificates:"
		echo "  oc describe certificate -n $CERT_NAMESPACE"
		echo
		echo "To use Pebble with auto-validation, reinstall with:"
		echo "  PEBBLE_ALWAYS_VALID=1 make install-pebble"
	fi
}

# Main execution
main() {
	print_header "Create Test Certificates"
	check_prerequisites
	create_test_certificates
	wait_for_certificates
	display_certificate_status
	display_next_steps
}

# Run main function
main
