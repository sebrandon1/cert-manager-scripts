#!/bin/bash

################################################################################
# Script: check-all.sh
# Description: Run all troubleshooting checks
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "========================================"
echo "  Complete System Diagnostics"
echo "========================================"
echo

# Check if we're logged in
if ! oc whoami &>/dev/null; then
	log_error "Not logged into OpenShift cluster"
	exit 1
fi

log_info "Cluster: $(oc whoami --show-server)"
log_info "User: $(oc whoami)"
echo

# Section 1: cert-manager
echo "========================================"
echo "  cert-manager Components"
echo "========================================"
echo

log_info "Checking cert-manager operator..."
if oc get csv -n cert-manager-operator 2>/dev/null | grep -q "Succeeded"; then
	echo "✅ cert-manager operator is installed"
else
	log_warn "cert-manager operator not found or not healthy"
fi

log_info "Checking cert-manager pods..."
if oc get pods -n cert-manager &>/dev/null; then
	oc get pods -n cert-manager
else
	log_warn "cert-manager namespace not found"
fi

echo

# Section 2: Pebble
echo "========================================"
echo "  Pebble ACME Server"
echo "========================================"
echo

if oc get namespace pebble &>/dev/null; then
	log_info "Checking Pebble pods..."
	oc get pods -n pebble

	echo
	log_info "Checking Pebble route..."
	if oc get route pebble-acme -n pebble &>/dev/null; then
		ROUTE=$(oc get route pebble-acme -n pebble -o jsonpath='{.spec.host}')
		echo "✅ Pebble route: https://$ROUTE"
	else
		log_warn "Pebble route not found"
	fi
else
	log_warn "Pebble namespace not found"
fi

echo

# Section 3: DNS Components
echo "========================================"
echo "  DNS-01 Components"
echo "========================================"
echo

if oc get namespace fake-dns &>/dev/null; then
	log_info "Checking fake DNS API..."
	oc get pods -n fake-dns
else
	log_info "Fake DNS not installed (only needed for DNS-01)"
fi

echo

# Section 4: ClusterIssuers
echo "========================================"
echo "  ClusterIssuers"
echo "========================================"
echo

if oc get clusterissuer &>/dev/null; then
	oc get clusterissuer
	echo

	# Check each issuer
	for issuer in $(oc get clusterissuer -o name 2>/dev/null | cut -d'/' -f2); do
		READY=$(oc get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
		if [ "$READY" = "True" ]; then
			echo "✅ $issuer is ready"
		else
			log_warn "$issuer is not ready (Status: $READY)"
		fi
	done
else
	log_warn "No ClusterIssuers found"
fi

echo

# Section 5: Certificates
echo "========================================"
echo "  Certificates"
echo "========================================"
echo

CERTS=$(oc get certificate -A -o json 2>/dev/null | jq -r '.items | length' || echo "0")

if [ "$CERTS" -gt 0 ]; then
	log_info "Found $CERTS certificate(s):"
	echo
	oc get certificate -A
	echo

	# Check for failed certificates
	FAILED=$(oc get certificate -A -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

	if [ -n "$FAILED" ]; then
		echo
		log_warn "Failed certificates:"
		for cert in $FAILED; do
			echo "  ❌ $cert"
		done
		echo
		echo "Run detailed check with:"
		echo "  ./scripts/troubleshooting/check-certificate.sh <name> <namespace>"
	fi
else
	log_info "No certificates found"
fi

echo

# Section 6: Active Challenges
echo "========================================"
echo "  Active Challenges"
echo "========================================"
echo

CHALLENGES=$(oc get challenge -A 2>/dev/null | grep -v "^NAMESPACE" | wc -l | xargs || echo "0")

if [ "$CHALLENGES" -gt 0 ]; then
	log_info "Found $CHALLENGES active challenge(s):"
	echo
	oc get challenge -A
else
	log_info "No active challenges"
fi

echo

# Section 7: Quick Health Summary
echo "========================================"
echo "  Health Summary"
echo "========================================"
echo

ISSUES=0

# Check cert-manager
if ! oc get deployment cert-manager -n cert-manager &>/dev/null; then
	log_error "cert-manager not found"
	ISSUES=$((ISSUES + 1))
fi

# Check if any issuer exists
if ! oc get clusterissuer &>/dev/null; then
	log_warn "No ClusterIssuers configured"
	ISSUES=$((ISSUES + 1))
fi

# Check if any issuer is ready
READY_ISSUERS=$(oc get clusterissuer -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l | xargs || echo "0")
if [ "$READY_ISSUERS" -eq 0 ] && oc get clusterissuer &>/dev/null; then
	log_warn "No ClusterIssuers are ready"
	ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
	echo "✅ No major issues detected"
else
	echo "⚠️  Found $ISSUES potential issue(s)"
fi

echo
echo "========================================"
echo "  Troubleshooting Tools"
echo "========================================"
echo
echo "Check specific certificate:"
echo "  ./scripts/troubleshooting/check-certificate.sh <name> <namespace>"
echo
echo "Check specific issuer:"
echo "  ./scripts/troubleshooting/check-issuer.sh <issuer-name>"
echo
echo "Diagnose HTTP-01 issues:"
echo "  ./scripts/troubleshooting/diagnose-http01.sh"
echo
echo "Diagnose DNS-01 issues:"
echo "  ./scripts/troubleshooting/diagnose-dns01.sh"
echo
