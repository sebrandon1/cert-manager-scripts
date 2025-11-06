#!/bin/bash

################################################################################
# Script: create-test-certificates.sh
# Description: Create test certificates using cert-manager
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/../yaml/certificates"

# Configuration (exported for envsubst)
export ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
export CERT_NAMESPACE="${CERT_NAMESPACE:-default}"

# Function to print colored messages
log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

log_detail() {
	echo -e "${BLUE}[DETAIL]${NC} $1"
}

# Function to print header
print_header() {
	echo
	echo "========================================"
	echo "  Create Test Certificates"
	echo "========================================"
	echo
}

# Function to check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	if ! command -v oc &>/dev/null; then
		log_error "oc command not found. Please install OpenShift CLI."
		exit 1
	fi

	if ! command -v envsubst &>/dev/null; then
		log_error "envsubst command not found. Please install gettext package."
		exit 1
	fi

	if ! oc whoami &>/dev/null; then
		log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
		exit 1
	fi

	# Check if cert-manager is installed
	if ! oc get deployment -n cert-manager cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		log_info "  Run: make install-cert-manager-operator"
		exit 1
	fi

	# Check if issuer exists
	if ! oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_error "ClusterIssuer '$ISSUER_NAME' not found."
		log_info "  Create an issuer first: make create-issuer"
		exit 1
	fi

	# Check if namespace exists
	if ! oc get namespace "$CERT_NAMESPACE" &>/dev/null; then
		log_warn "Namespace '$CERT_NAMESPACE' does not exist."
		read -p "Create namespace '$CERT_NAMESPACE'? (y/N): " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			oc create namespace "$CERT_NAMESPACE"
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
	if oc get certificate "$cert_name" -n "$CERT_NAMESPACE" &>/dev/null; then
		log_warn "Certificate '$cert_name' already exists in namespace '$CERT_NAMESPACE'."
		return 0
	fi

	envsubst <"$YAML_DIR/test-certificate.yaml" | oc apply -f -

	if [ $? -eq 0 ]; then
		log_info "Certificate '$cert_name' created."
	else
		log_error "Failed to create certificate '$cert_name'."
	fi
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

# Function to wait for certificates
wait_for_certificates() {
	log_info "Waiting for certificates to be issued..."
	echo

	local max_wait=60
	local wait_time=0

	while [ $wait_time -lt $max_wait ]; do
		local all_ready=true

		# Check each certificate
		for cert in test-cert-simple test-cert-app test-cert-api; do
			if oc get certificate "$cert" -n "$CERT_NAMESPACE" &>/dev/null; then
				local ready=$(oc get certificate "$cert" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

				if [ "$ready" != "True" ]; then
					all_ready=false
				fi
			fi
		done

		if [ "$all_ready" = true ]; then
			log_info "All certificates are ready!"
			break
		fi

		if [ $((wait_time % 10)) -eq 0 ]; then
			echo -n " [${wait_time}s/${max_wait}s]"
		else
			echo -n "."
		fi

		sleep 2
		wait_time=$((wait_time + 2))
	done
	echo

	if [ $wait_time -ge $max_wait ]; then
		log_warn "Timeout waiting for all certificates to be ready."
		log_info "This is normal if using PEBBLE_ALWAYS_VALID=0 without proper DNS/HTTP setup."
		log_info "Check certificate status below for details."
	fi
}

# Function to display certificate status
display_certificate_status() {
	echo
	log_info "========================================"
	log_info "  Certificate Status"
	log_info "========================================"
	echo

	log_info "Certificates:"
	oc get certificate -n "$CERT_NAMESPACE" 2>/dev/null || echo "No certificates found"

	echo
	log_info "Certificate Requests:"
	oc get certificaterequest -n "$CERT_NAMESPACE" 2>/dev/null || echo "No certificate requests found"

	echo
	log_info "ACME Orders:"
	oc get order -n "$CERT_NAMESPACE" 2>/dev/null || echo "No orders found"

	echo
	log_info "ACME Challenges:"
	oc get challenge -n "$CERT_NAMESPACE" 2>/dev/null || echo "No challenges found"
}

# Function to display next steps
display_next_steps() {
	echo
	log_info "========================================"
	log_info "  Next Steps"
	log_info "========================================"
	echo
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
	local failed_certs=$(oc get certificate -n "$CERT_NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | .metadata.name' | wc -l | tr -d ' ')

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
	print_header
	check_prerequisites
	create_test_certificates
	wait_for_certificates
	display_certificate_status
	display_next_steps
}

# Run main function
main
