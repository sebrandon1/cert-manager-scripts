#!/bin/bash

################################################################################
# Script: diagnose-http01.sh
# Description: Diagnose HTTP-01 challenge issues
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

print_header "HTTP-01 Challenge Diagnostics"

# Check cert-manager
log_info "Checking cert-manager..."
if oc get deployment cert-manager -n cert-manager &>/dev/null; then
	READY=$(oc get deployment cert-manager -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
	if [ "$READY" -gt 0 ]; then
		echo "✅ cert-manager is running"
	else
		log_error "cert-manager has no ready replicas"
	fi
else
	log_error "cert-manager deployment not found"
fi

echo

# Check Pebble
log_info "Checking Pebble ACME server..."
if oc get deployment pebble -n pebble &>/dev/null; then
	READY=$(oc get deployment pebble -n pebble -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
	if [ "$READY" -gt 0 ]; then
		echo "✅ Pebble is running"

		# Get Pebble route
		ROUTE=$(oc get route pebble-acme -n pebble -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
		if [ -n "$ROUTE" ]; then
			log_debug "Pebble route: https://$ROUTE"
		fi
	else
		log_error "Pebble has no ready replicas"
	fi
else
	log_warn "Pebble deployment not found"
fi

echo

# Check HTTP-01 ClusterIssuers
log_info "Checking HTTP-01 ClusterIssuers..."
HTTP01_ISSUERS=$(oc get clusterissuer -o json | jq -r '.items[] | select(.spec.acme.solvers[]?.http01 != null) | .metadata.name' 2>/dev/null || echo "")

if [ -n "$HTTP01_ISSUERS" ]; then
	for issuer in $HTTP01_ISSUERS; do
		READY=$(oc get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
		if [ "$READY" = "True" ]; then
			echo "✅ $issuer is ready"
		else
			log_warn "$issuer is not ready (Status: $READY)"
		fi
	done
else
	log_warn "No HTTP-01 ClusterIssuers found"
fi

echo

# Check for active HTTP-01 challenges
log_info "Checking for active HTTP-01 challenges..."
CHALLENGES=$(oc get challenge -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.solver.http01 != null) | "\(.metadata.namespace)/\(.metadata.name)"' || echo "")

if [ -n "$CHALLENGES" ]; then
	echo "Found HTTP-01 challenges:"
	echo

	for challenge in $CHALLENGES; do
		NAMESPACE=$(echo "$challenge" | cut -d'/' -f1)
		NAME=$(echo "$challenge" | cut -d'/' -f2)

		log_debug "Challenge: $NAME (namespace: $NAMESPACE)"

		STATE=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
		log_debug "  State: $STATE"

		# Get challenge details
		DOMAIN=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.spec.dnsName}' 2>/dev/null || echo "unknown")
		TOKEN=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.spec.token}' 2>/dev/null || echo "unknown")
		KEY=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.spec.key}' 2>/dev/null || echo "unknown")

		log_debug "  Domain: $DOMAIN"
		log_debug "  Token: ${TOKEN:0:20}..."

		# Check if challenge service exists
		if oc get service -n "$NAMESPACE" -l "acme.cert-manager.io/http01-solver=true" &>/dev/null; then
			echo "  ✅ Challenge solver service exists"
		else
			log_warn "  Challenge solver service not found"
		fi

		echo
	done
else
	log_info "No active HTTP-01 challenges found"
fi

echo

# Check network connectivity
log_info "Checking network connectivity..."
if ./scripts/check-cluster-network.sh &>/dev/null; then
	echo "✅ Network check passed"
else
	log_warn "Network check failed or script not found"
fi

echo
echo "========================================"
echo "  Recent cert-manager Logs"
echo "========================================"
echo
oc logs -n cert-manager deployment/cert-manager --tail=20 2>/dev/null || log_warn "Could not fetch logs"

echo
echo "========================================"
echo "  Recent Pebble Logs"
echo "========================================"
echo
oc logs -n pebble -l app=pebble --tail=20 2>/dev/null || log_warn "Could not fetch Pebble logs"

echo
echo "========================================"
echo "  Recommendations"
echo "========================================"
echo
echo "1. Ensure Pebble is configured with PEBBLE_ALWAYS_VALID=1 for testing:"
echo "   PEBBLE_ALWAYS_VALID=1 make install-pebble"
echo
echo "2. Check HTTP-01 issuer configuration:"
echo "   ./scripts/troubleshooting/check-issuer.sh pebble-issuer"
echo
echo "3. Check specific certificate:"
echo "   ./scripts/troubleshooting/check-certificate.sh <cert-name> <namespace>"
echo
echo "4. View full cert-manager logs:"
echo "   oc logs -n cert-manager deployment/cert-manager -f"
echo
