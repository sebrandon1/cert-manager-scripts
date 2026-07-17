#!/bin/bash

################################################################################
# Script: create-apiserver-certificate.sh
# Description: Create a cert-manager Certificate for the OpenShift API server
#
# This script creates a Certificate CR that can be used to issue a certificate
# for the API server using cert-manager and a local ACME provider (Pebble).
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

# Configuration
ISSUER_NAME="${ISSUER_NAME:-pebble-issuer}"
CERT_NAMESPACE="${CERT_NAMESPACE:-openshift-config}"
CERT_NAME="apiserver-cert"
SECRET_NAME="apiserver-cert-tls"

check_prerequisites() {
	log_info "Checking prerequisites..."

	require_cmd oc
	require_cluster

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
	log_debug "API Server URL: $API_URL"

	# Extract hostname from URL
	API_HOST=$(echo "$API_URL" | sed -E 's|https?://([^:/]+).*|\1|')
	log_debug "API Server Hostname: $API_HOST"

	# Get cluster base domain
	CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
	if [ -n "$CLUSTER_DOMAIN" ]; then
		log_debug "Cluster Domain: $CLUSTER_DOMAIN"
		# Extract base domain (remove apps. prefix if present)
		BASE_DOMAIN="${CLUSTER_DOMAIN#apps.}"
		log_debug "Base Domain: $BASE_DOMAIN"
	else
		log_warn "Could not determine cluster domain"
		BASE_DOMAIN=""
	fi

	echo
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
	if cat <<EOF | oc apply -f -; then
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
		log_info "Certificate '$CERT_NAME' created successfully in namespace '$CERT_NAMESPACE'"
	else
		log_error "Failed to create certificate '$CERT_NAME'"
		exit 1
	fi
}

check_apiserver_cert_ready() {
	oc whoami &>/dev/null || return 1
	local ready
	ready=$(oc get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
	[ "$ready" = "True" ]
}

wait_for_certificate() {
	log_info "Waiting for certificate to be issued..."

	local max_attempts=$(((${CERT_WAIT_TIMEOUT:-60} + 1) / 2))
	if wait_for_condition "$max_attempts" 2 check_apiserver_cert_ready; then
		log_success "Certificate is READY!"
	else
		log_warn "Timeout waiting for certificate to be ready."
		log_info "The certificate resource was created - it may become ready later."
		log_info "Check certificate status: oc describe certificate $CERT_NAME -n $CERT_NAMESPACE"
	fi
}

display_certificate_info() {
	print_header "Certificate Information"

	# Check cluster connectivity first
	if ! oc whoami &>/dev/null; then
		log_warn "Cluster connectivity lost - skipping certificate info display"
		return 0
	fi

	log_info "Certificate status:"
	oc get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" 2>/dev/null || log_warn "Cannot retrieve certificate status"
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
	print_header "Next Steps"

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

To verify the certificate was created:
   make verify-apiserver-cert

To verify the certificate without applying:
   oc get certificate $CERT_NAME -n $CERT_NAMESPACE
   oc describe certificate $CERT_NAME -n $CERT_NAMESPACE

To view the certificate:
   oc get secret $SECRET_NAME -n $CERT_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

EOF
}

main() {
	print_header "Create API Server Certificate"
	check_prerequisites
	get_api_server_info
	ensure_namespace "$CERT_NAMESPACE"
	create_certificate
	wait_for_certificate || true
	display_certificate_info
	display_next_steps
}

main
