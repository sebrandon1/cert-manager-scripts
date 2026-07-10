#!/bin/bash

################################################################################
# Script: check-issuer.sh
# Description: Check ClusterIssuer status and configuration
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Function to check a single ClusterIssuer
check_single_issuer() {
	local ISSUER_NAME=$1

	print_header "ClusterIssuer Diagnostics"
	log_info "ClusterIssuer: $ISSUER_NAME"
	echo

	# Get issuer status
	log_info "ClusterIssuer Status:"
	oc get clusterissuer "$ISSUER_NAME"
	echo

	# Check if issuer is ready
	READY=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

	if [ "$READY" = "True" ]; then
		echo "✅ ClusterIssuer is READY!"
	else
		log_warn "ClusterIssuer is NOT ready (Status: $READY)"
	fi

	echo
	log_info "ClusterIssuer Configuration:"
	echo

	# Get ACME server URL
	ACME_SERVER=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.server}' 2>/dev/null || echo "N/A")
	log_debug "ACME Server: $ACME_SERVER"

	# Get email
	EMAIL=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.email}' 2>/dev/null || echo "N/A")
	log_debug "Email: $EMAIL"

	# Check solver type
	SOLVER_TYPE=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.solvers[0].http01}' 2>/dev/null)
	if [ -n "$SOLVER_TYPE" ]; then
		log_debug "Solver Type: HTTP-01"
		INGRESS_CLASS=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.solvers[0].http01.ingress.class}' 2>/dev/null || echo "N/A")
		log_debug "Ingress Class: $INGRESS_CLASS"
	else
		SOLVER_TYPE=$(oc get clusterissuer "$ISSUER_NAME" -o jsonpath='{.spec.acme.solvers[0].dns01}' 2>/dev/null)
		if [ -n "$SOLVER_TYPE" ]; then
			log_debug "Solver Type: DNS-01"
		else
			log_debug "Solver Type: Unknown"
		fi
	fi

	echo
	log_info "Detailed Configuration:"
	oc describe clusterissuer "$ISSUER_NAME"

	print_header "Testing ACME Server Connectivity"

	# Test Pebble connectivity if using Pebble
	if [[ "$ACME_SERVER" == *"pebble"* ]]; then
		log_info "Testing Pebble connectivity..."

		# Check if Pebble is running
		if oc get deployment pebble -n pebble &>/dev/null; then
			READY_REPLICAS=$(oc get deployment pebble -n pebble -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
			if [ "$READY_REPLICAS" -gt 0 ]; then
				echo "✅ Pebble deployment is running"
			else
				log_warn "Pebble deployment has no ready replicas"
			fi

			# Try to access ACME directory
			log_info "Testing ACME directory endpoint..."
			if oc run --rm -i --restart=Never test-acme-$RANDOM --image=curlimages/curl -- curl -ks "$ACME_SERVER" 2>/dev/null | grep -q "directory"; then
				echo "✅ ACME directory is accessible"
			else
				log_warn "Could not access ACME directory"
			fi
		else
			log_warn "Pebble deployment not found in 'pebble' namespace"
		fi
	else
		log_info "Not using Pebble, skipping connectivity test"
	fi

	print_header "Troubleshooting Commands"
	echo "View full YAML configuration:"
	echo "  oc get clusterissuer $ISSUER_NAME -o yaml"
	echo
	echo "Check ACME account status:"
	echo "  oc get clusterissuer $ISSUER_NAME -o jsonpath='{.status.acme.uri}'"
	echo
	echo "Test certificate creation:"
	echo "  make create-certs"
	echo
}

require_cmd oc jq

# Main logic
if [ $# -eq 0 ]; then
	# No arguments - check all ClusterIssuers
	print_header "Checking All ClusterIssuers"

	# Get all ClusterIssuers
	ISSUERS=$(oc get clusterissuer -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

	if [ -z "$ISSUERS" ]; then
		log_warn "No ClusterIssuers found"
		exit 0
	fi

	# Count ClusterIssuers
	ISSUER_COUNT=$(echo "$ISSUERS" | wc -l | xargs)
	log_info "Found $ISSUER_COUNT ClusterIssuer(s)"
	echo

	# Check each ClusterIssuer
	while IFS= read -r issuer; do
		check_single_issuer "$issuer"
		echo
		echo "----------------------------------------"
		echo
	done <<<"$ISSUERS"

elif [ $# -eq 1 ]; then
	# ClusterIssuer name provided
	ISSUER_NAME=$1

	# Check if issuer exists
	if ! oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_error "ClusterIssuer '$ISSUER_NAME' not found"
		echo
		log_info "Available ClusterIssuers:"
		oc get clusterissuer 2>/dev/null || echo "  None found"
		exit 1
	fi

	check_single_issuer "$ISSUER_NAME"
else
	echo "Usage: $0 [<clusterissuer-name>]"
	echo
	echo "Examples:"
	echo "  $0                      # Check all ClusterIssuers"
	echo "  $0 pebble-issuer        # Check specific ClusterIssuer"
	echo "  $0 pebble-dns01-issuer  # Check specific ClusterIssuer"
	exit 1
fi
