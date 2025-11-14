#!/bin/bash

################################################################################
# Script: create-apiserver-certificate.sh
# Description: Create a cert-manager Certificate for the OpenShift API server
#
# This script creates a Certificate CR that can be used to issue a certificate
# for the API server using cert-manager and a local ACME provider (Pebble).
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

# Configuration
ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
CERT_NAMESPACE="${CERT_NAMESPACE:-openshift-config}"
CERT_NAME="apiserver-cert"
SECRET_NAME="apiserver-cert-tls"

print_header() {
	echo
	echo "========================================"
	echo "  Create API Server Certificate"
	echo "========================================"
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."

	if ! command -v oc &>/dev/null; then
		log_error "oc command not found. Please install OpenShift CLI."
		exit 1
	fi

	if ! oc whoami &>/dev/null; then
		log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
		exit 1
	fi

	# Check if cert-manager is installed
	if ! oc get deployment -n cert-manager cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		exit 1
	fi

	# Check if issuer exists
	if ! oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_error "ClusterIssuer '$ISSUER_NAME' not found."
		log_info "  Create an issuer first: make create-issuer"
		exit 1
	fi

	log_info "Prerequisites check passed."
}

get_api_server_info() {
	log_info "Gathering API server information..."

	# Get the API server URL
	API_URL=$(oc whoami --show-server)
	log_detail "API Server URL: $API_URL"

	# Extract hostname from URL
	API_HOST=$(echo "$API_URL" | sed -E 's|https?://([^:/]+).*|\1|')
	log_detail "API Server Hostname: $API_HOST"

	# Get cluster base domain
	CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
	if [ -n "$CLUSTER_DOMAIN" ]; then
		log_detail "Cluster Domain: $CLUSTER_DOMAIN"
		# Extract base domain (remove apps. prefix if present)
		BASE_DOMAIN=$(echo "$CLUSTER_DOMAIN" | sed 's/^apps\.//')
		log_detail "Base Domain: $BASE_DOMAIN"
	else
		log_warn "Could not determine cluster domain"
		BASE_DOMAIN=""
	fi

	echo
}

create_namespace_if_needed() {
	if ! oc get namespace "$CERT_NAMESPACE" &>/dev/null; then
		log_info "Creating namespace: $CERT_NAMESPACE"
		oc create namespace "$CERT_NAMESPACE"
	else
		log_info "Namespace '$CERT_NAMESPACE' already exists"
	fi
}

create_certificate() {
	log_info "Creating Certificate CR for API server..."
	echo

	# Build DNS names list
	DNS_NAMES="- \"$API_HOST\""

	# Add additional SANs if we can determine them
	if [ -n "$BASE_DOMAIN" ]; then
		DNS_NAMES="$DNS_NAMES
  - \"api.$BASE_DOMAIN\""
	fi

	# Create the Certificate CR
	cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $CERT_NAME
  namespace: $CERT_NAMESPACE
spec:
  secretName: $SECRET_NAME
  issuerRef:
    name: $ISSUER_NAME
    kind: ClusterIssuer
  dnsNames:
  $DNS_NAMES
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

	if [ $? -eq 0 ]; then
		log_info "Certificate '$CERT_NAME' created successfully in namespace '$CERT_NAMESPACE'"
	else
		log_error "Failed to create certificate '$CERT_NAME'"
		exit 1
	fi
}

wait_for_certificate() {
	log_info "Waiting for certificate to be issued..."
	echo

	local max_wait=120
	local wait_time=0

	while [ $wait_time -lt $max_wait ]; do
		local ready=$(oc get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

		if [ "$ready" = "True" ]; then
			log_info "✅ Certificate is READY!"
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
		log_warn "Timeout waiting for certificate to be ready."
		log_info "Check certificate status: oc describe certificate $CERT_NAME -n $CERT_NAMESPACE"
		return 1
	fi

	return 0
}

display_certificate_info() {
	echo
	log_info "========================================"
	log_info "  Certificate Information"
	log_info "========================================"
	echo

	log_info "Certificate status:"
	oc get certificate "$CERT_NAME" -n "$CERT_NAMESPACE"
	echo

	log_info "Certificate secret:"
	oc get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" 2>/dev/null || log_warn "Secret not yet created"
	echo

	# If certificate is ready, show details
	if oc get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
		log_info "Certificate details:"
		oc get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -text -noout | head -20
	fi
}

display_next_steps() {
	echo
	log_info "========================================"
	log_info "  Next Steps"
	log_info "========================================"
	echo

	cat <<EOF
The API server certificate has been created but NOT yet applied to the cluster.

⚠️  WARNING: Applying this certificate to the API server will:
   - Temporarily disrupt API server connectivity
   - Require careful validation
   - Should be tested in a non-production environment first

To apply this certificate to the API server:
   1. Backup current API server certificates
   2. Update the APIServer configuration to reference the new secret
   3. Wait for the API server to roll out the changes
   4. Verify cluster access still works

For detailed instructions, see the documentation or run:
   ./scripts/apply-apiserver-certificate.sh

To verify the certificate without applying:
   oc get certificate $CERT_NAME -n $CERT_NAMESPACE
   oc describe certificate $CERT_NAME -n $CERT_NAMESPACE

To view the certificate:
   oc get secret $SECRET_NAME -n $CERT_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

EOF
}

main() {
	print_header
	check_prerequisites
	get_api_server_info
	create_namespace_if_needed
	create_certificate
	wait_for_certificate || true
	display_certificate_info
	display_next_steps
}

main
