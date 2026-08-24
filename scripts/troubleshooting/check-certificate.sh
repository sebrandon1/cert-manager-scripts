#!/bin/bash

################################################################################
# Script: check-certificate.sh
# Description: Check certificate status and show detailed troubleshooting info
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Function to check a single certificate
check_single_certificate() {
	local CERT_NAME=$1
	local NAMESPACE=$2

	print_header "Certificate Diagnostics"
	log_info "Certificate: $CERT_NAME"
	log_info "Namespace: $NAMESPACE"
	echo

	# Check if certificate exists
	if ! "$KUBE_CLI" get certificate "$CERT_NAME" -n "$NAMESPACE" &>/dev/null; then
		log_error "Certificate '$CERT_NAME' not found in namespace '$NAMESPACE'"
		exit 1
	fi

	# Get certificate status
	log_info "Certificate Status:"
	"$KUBE_CLI" get certificate "$CERT_NAME" -n "$NAMESPACE"
	echo

	# Check if certificate is ready
	READY=$("$KUBE_CLI" get certificate "$CERT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

	if [ "$READY" = "True" ]; then
		echo "✅ Certificate is READY!"
		echo

		# Show certificate details
		log_info "Certificate Secret:"
		SECRET_NAME=$("$KUBE_CLI" get certificate "$CERT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.secretName}')
		"$KUBE_CLI" get secret "$SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || log_warn "Secret not found"

		echo
		log_debug "Certificate Details:"
		echo "To view certificate:"
		echo "  $KUBE_CLI get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout"

	else
		log_warn "Certificate is NOT ready (Status: $READY)"
		echo

		# Show detailed certificate info
		log_info "Certificate Details:"
		"$KUBE_CLI" describe certificate "$CERT_NAME" -n "$NAMESPACE"

		print_header "Checking Certificate Requests"

		# Find related CertificateRequests
		CR_LIST=$("$KUBE_CLI" get certificaterequest -n "$NAMESPACE" -o json | jq -r ".items[] | select(.metadata.ownerReferences[]?.name==\"$CERT_NAME\") | .metadata.name" 2>/dev/null || echo "")

		if [ -n "$CR_LIST" ]; then
			while IFS= read -r cr; do
				[[ -z "$cr" ]] && continue
				log_info "CertificateRequest: $cr"
				"$KUBE_CLI" describe certificaterequest "$cr" -n "$NAMESPACE"
				echo
			done <<<"$CR_LIST"
		else
			log_warn "No CertificateRequests found"
		fi

		print_header "Checking ACME Orders"

		# Check orders
		if "$KUBE_CLI" get order -n "$NAMESPACE" &>/dev/null; then
			ORDERS=$("$KUBE_CLI" get order -n "$NAMESPACE" -o name 2>/dev/null || echo "")
			if [ -n "$ORDERS" ]; then
				while IFS= read -r order; do
					[[ -z "$order" ]] && continue
					log_info "Order: $(basename "$order")"
					"$KUBE_CLI" describe "$order" -n "$NAMESPACE"
					echo
				done <<<"$ORDERS"
			else
				log_warn "No Orders found"
			fi
		else
			log_warn "No Orders found"
		fi

		print_header "Checking ACME Challenges"

		# Check challenges
		if "$KUBE_CLI" get challenge -n "$NAMESPACE" &>/dev/null; then
			CHALLENGES=$("$KUBE_CLI" get challenge -n "$NAMESPACE" -o name 2>/dev/null || echo "")
			if [ -n "$CHALLENGES" ]; then
				while IFS= read -r challenge; do
					[[ -z "$challenge" ]] && continue
					log_info "Challenge: $(basename "$challenge")"
					"$KUBE_CLI" describe "$challenge" -n "$NAMESPACE"
					echo
				done <<<"$CHALLENGES"
			else
				log_warn "No Challenges found"
			fi
		else
			log_warn "No Challenges found"
		fi
	fi

	print_header "Troubleshooting Commands"
	echo "Check cert-manager logs:"
	echo "  $KUBE_CLI logs -n cert-manager deployment/cert-manager --tail=50"
	echo
	echo "Check Pebble logs:"
	echo "  $KUBE_CLI logs -n pebble -l app=pebble --tail=50"
	echo
	echo "Watch certificate status:"
	echo "  watch $KUBE_CLI get certificate,certificaterequest,order,challenge -n $NAMESPACE"
	echo
}

require_cmd "$KUBE_CLI" jq

# Main logic
if [ $# -eq 0 ]; then
	# No arguments - check all certificates
	print_header "Checking All Certificates"

	# Get all certificates across all namespaces
	CERTS=$("$KUBE_CLI" get certificate -A -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' 2>/dev/null || echo "")

	if [ -z "$CERTS" ]; then
		log_warn "No certificates found in any namespace"
		exit 0
	fi

	# Count certificates
	CERT_COUNT=$(echo "$CERTS" | wc -l | xargs)
	log_info "Found $CERT_COUNT certificate(s)"
	echo

	# Check each certificate
	while IFS= read -r line; do
		NAMESPACE=$(echo "$line" | awk '{print $1}')
		CERT_NAME=$(echo "$line" | awk '{print $2}')
		check_single_certificate "$CERT_NAME" "$NAMESPACE"
		echo
		echo "----------------------------------------"
		echo
	done <<<"$CERTS"

elif [ $# -eq 2 ]; then
	# Certificate name and namespace provided
	CERT_NAME=$1
	NAMESPACE=$2
	check_single_certificate "$CERT_NAME" "$NAMESPACE"
else
	echo "Usage: $0 [<certificate-name> <namespace>]"
	echo
	echo "Examples:"
	echo "  $0                              # Check all certificates"
	echo "  $0 test-cert-simple default     # Check specific certificate"
	exit 1
fi
