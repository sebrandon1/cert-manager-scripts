#!/bin/bash

################################################################################
# Script: check-all.sh
# Description: Run all troubleshooting checks
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

print_header "Complete System Diagnostics"

require_cmd "$KUBE_CLI" jq
require_cluster

if [[ "$KUBE_CLI" == "oc" ]]; then
	log_info "Cluster: $("$KUBE_CLI" whoami --show-server)"
	log_info "User: $("$KUBE_CLI" whoami)"
else
	log_info "Cluster: $("$KUBE_CLI" config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
	log_info "Context: $("$KUBE_CLI" config current-context)"
fi
echo

# Section 1: cert-manager
print_header "cert-manager Components"

if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
	log_info "Checking cert-manager operator..."
	if "$KUBE_CLI" get csv -n cert-manager-operator 2>/dev/null | grep -q "Succeeded"; then
		echo "✅ cert-manager operator is installed"
	else
		log_warn "cert-manager operator not found or not healthy"
	fi
else
	log_info "Skipping cert-manager operator CSV check (OpenShift-only)"
fi

log_info "Checking cert-manager pods..."
if "$KUBE_CLI" get pods -n cert-manager &>/dev/null; then
	"$KUBE_CLI" get pods -n cert-manager
else
	log_warn "cert-manager namespace not found"
fi

echo

# Section 2: Pebble
print_header "Pebble ACME Server"

if "$KUBE_CLI" get namespace pebble &>/dev/null; then
	log_info "Checking Pebble pods..."
	"$KUBE_CLI" get pods -n pebble

	if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
		echo
		log_info "Checking Pebble route..."
		if "$KUBE_CLI" get route pebble-acme -n pebble &>/dev/null; then
			ROUTE=$("$KUBE_CLI" get route pebble-acme -n pebble -o jsonpath='{.spec.host}')
			echo "✅ Pebble route: https://$ROUTE"
		else
			log_warn "Pebble route not found"
		fi
	fi
else
	log_warn "Pebble namespace not found"
fi

echo

# Section 3: DNS Components
print_header "DNS-01 Components"

if "$KUBE_CLI" get namespace fake-dns &>/dev/null; then
	log_info "Checking fake DNS API..."
	"$KUBE_CLI" get pods -n fake-dns
else
	log_info "Fake DNS not installed (only needed for DNS-01)"
fi

echo

# Section 4: ClusterIssuers
print_header "ClusterIssuers"

if "$KUBE_CLI" get clusterissuer &>/dev/null; then
	"$KUBE_CLI" get clusterissuer
	echo

	# Check each issuer
	for issuer in $("$KUBE_CLI" get clusterissuer -o name 2>/dev/null | cut -d'/' -f2); do
		READY=$("$KUBE_CLI" get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
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
print_header "Certificates"

CERTS=$("$KUBE_CLI" get certificate -A -o json 2>/dev/null | jq -r '.items | length' || echo "0")

if [ "$CERTS" -gt 0 ]; then
	log_info "Found $CERTS certificate(s):"
	echo
	"$KUBE_CLI" get certificate -A
	echo

	# Check for failed certificates
	FAILED=$("$KUBE_CLI" get certificate -A -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

	if [ -n "$FAILED" ]; then
		echo
		log_warn "Failed certificates:"
		while IFS= read -r cert; do
			[[ -z "$cert" ]] && continue
			echo "  ❌ $cert"
		done <<<"$FAILED"
		echo
		echo "Run detailed check with:"
		echo "  ./scripts/troubleshooting/check-certificate.sh <name> <namespace>"
	fi
else
	log_info "No certificates found"
fi

echo

# Section 6: Active Challenges
print_header "Active Challenges"

CHALLENGES=$("$KUBE_CLI" get challenge -A 2>/dev/null | grep -cv "^NAMESPACE" || echo "0")

if [ "$CHALLENGES" -gt 0 ]; then
	log_info "Found $CHALLENGES active challenge(s):"
	echo
	"$KUBE_CLI" get challenge -A
else
	log_info "No active challenges"
fi

echo

# Section 7: Quick Health Summary
print_header "Health Summary"

ISSUES=0

# Check cert-manager
if ! "$KUBE_CLI" get deployment cert-manager -n cert-manager &>/dev/null; then
	log_error "cert-manager not found"
	ISSUES=$((ISSUES + 1))
fi

# Check if any issuer exists
if ! "$KUBE_CLI" get clusterissuer &>/dev/null; then
	log_warn "No ClusterIssuers configured"
	ISSUES=$((ISSUES + 1))
fi

# Check if any issuer is ready
READY_ISSUERS=$("$KUBE_CLI" get clusterissuer -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l | xargs || echo "0")
if [ "$READY_ISSUERS" -eq 0 ] && "$KUBE_CLI" get clusterissuer &>/dev/null; then
	log_warn "No ClusterIssuers are ready"
	ISSUES=$((ISSUES + 1))
fi

if [ "$ISSUES" -eq 0 ]; then
	echo "✅ No major issues detected"
else
	echo "⚠️  Found $ISSUES potential issue(s)"
fi

echo
print_header "Troubleshooting Tools"

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

if [ "$ISSUES" -gt 0 ]; then
	exit 1
fi
