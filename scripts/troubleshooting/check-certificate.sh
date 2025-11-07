#!/bin/bash

################################################################################
# Script: check-certificate.sh
# Description: Check certificate status and show detailed troubleshooting info
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

# Check if certificate name and namespace provided
if [ $# -lt 2 ]; then
	echo "Usage: $0 <certificate-name> <namespace>"
	echo
	echo "Example:"
	echo "  $0 test-cert-simple default"
	exit 1
fi

CERT_NAME=$1
NAMESPACE=$2

echo
echo "========================================"
echo "  Certificate Diagnostics"
echo "========================================"
echo
log_info "Certificate: $CERT_NAME"
log_info "Namespace: $NAMESPACE"
echo

# Check if certificate exists
if ! oc get certificate "$CERT_NAME" -n "$NAMESPACE" &>/dev/null; then
	log_error "Certificate '$CERT_NAME' not found in namespace '$NAMESPACE'"
	exit 1
fi

# Get certificate status
log_info "Certificate Status:"
oc get certificate "$CERT_NAME" -n "$NAMESPACE"
echo

# Check if certificate is ready
READY=$(oc get certificate "$CERT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$READY" = "True" ]; then
	echo "✅ Certificate is READY!"
	echo

	# Show certificate details
	log_info "Certificate Secret:"
	SECRET_NAME=$(oc get certificate "$CERT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.secretName}')
	oc get secret "$SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || log_warn "Secret not found"

	echo
	log_info "Certificate Details:"
	echo "To view certificate:"
	echo "  oc get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout"

else
	log_warn "Certificate is NOT ready (Status: $READY)"
	echo

	# Show detailed certificate info
	log_info "Certificate Details:"
	oc describe certificate "$CERT_NAME" -n "$NAMESPACE"

	echo
	echo "========================================"
	echo "  Checking Certificate Requests"
	echo "========================================"
	echo

	# Find related CertificateRequests
	CR_LIST=$(oc get certificaterequest -n "$NAMESPACE" -o json | jq -r ".items[] | select(.metadata.ownerReferences[]?.name==\"$CERT_NAME\") | .metadata.name" 2>/dev/null || echo "")

	if [ -n "$CR_LIST" ]; then
		for cr in $CR_LIST; do
			log_info "CertificateRequest: $cr"
			oc describe certificaterequest "$cr" -n "$NAMESPACE"
			echo
		done
	else
		log_warn "No CertificateRequests found"
	fi

	echo
	echo "========================================"
	echo "  Checking ACME Orders"
	echo "========================================"
	echo

	# Check orders
	if oc get order -n "$NAMESPACE" &>/dev/null; then
		ORDERS=$(oc get order -n "$NAMESPACE" -o name 2>/dev/null || echo "")
		if [ -n "$ORDERS" ]; then
			for order in $ORDERS; do
				log_info "Order: $(basename $order)"
				oc describe "$order" -n "$NAMESPACE"
				echo
			done
		else
			log_warn "No Orders found"
		fi
	else
		log_warn "No Orders found"
	fi

	echo
	echo "========================================"
	echo "  Checking ACME Challenges"
	echo "========================================"
	echo

	# Check challenges
	if oc get challenge -n "$NAMESPACE" &>/dev/null; then
		CHALLENGES=$(oc get challenge -n "$NAMESPACE" -o name 2>/dev/null || echo "")
		if [ -n "$CHALLENGES" ]; then
			for challenge in $CHALLENGES; do
				log_info "Challenge: $(basename $challenge)"
				oc describe "$challenge" -n "$NAMESPACE"
				echo
			done
		else
			log_warn "No Challenges found"
		fi
	else
		log_warn "No Challenges found"
	fi
fi

echo
echo "========================================"
echo "  Troubleshooting Commands"
echo "========================================"
echo
echo "Check cert-manager logs:"
echo "  oc logs -n cert-manager deployment/cert-manager --tail=50"
echo
echo "Check Pebble logs:"
echo "  oc logs -n pebble -l app=pebble --tail=50"
echo
echo "Watch certificate status:"
echo "  watch oc get certificate,certificaterequest,order,challenge -n $NAMESPACE"
echo
