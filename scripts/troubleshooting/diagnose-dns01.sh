#!/bin/bash

################################################################################
# Script: diagnose-dns01.sh
# Description: Diagnose DNS-01 challenge issues
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

print_header "DNS-01 Challenge Diagnostics"

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

		# Check if using ALWAYS_VALID
		ALWAYS_VALID=$(oc get deployment pebble -n pebble -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PEBBLE_VA_ALWAYS_VALID")].value}' 2>/dev/null || echo "0")
		if [ "$ALWAYS_VALID" = "1" ]; then
			log_debug "Pebble ALWAYS_VALID: enabled (all challenges auto-succeed)"
		else
			log_debug "Pebble ALWAYS_VALID: disabled (real DNS validation required)"
		fi
	else
		log_error "Pebble has no ready replicas"
	fi
else
	log_warn "Pebble deployment not found"
fi

echo

# Check challenge test server
log_info "Checking Pebble challenge test server..."
if oc get deployment pebble-challtestsrv -n pebble &>/dev/null; then
	READY=$(oc get deployment pebble-challtestsrv -n pebble -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
	if [ "$READY" -gt 0 ]; then
		echo "✅ Challenge test server is running"
	else
		log_warn "Challenge test server has no ready replicas"
	fi
else
	log_warn "Challenge test server not found"
fi

echo

# Check fake DNS API
log_info "Checking fake DNS API..."
if oc get deployment fake-dns-api -n fake-dns &>/dev/null; then
	READY=$(oc get deployment fake-dns-api -n fake-dns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
	if [ "$READY" -gt 0 ]; then
		echo "✅ Fake DNS API is running"
	else
		log_warn "Fake DNS API has no ready replicas"
	fi
else
	log_warn "Fake DNS API not found (required for air-gapped DNS-01)"
fi

echo

# Check DNS-01 ClusterIssuers
log_info "Checking DNS-01 ClusterIssuers..."
DNS01_ISSUERS=$(oc get clusterissuer -o json | jq -r '.items[] | select(.spec.acme.solvers[]?.dns01 != null) | .metadata.name' 2>/dev/null || echo "")

if [ -n "$DNS01_ISSUERS" ]; then
	for issuer in $DNS01_ISSUERS; do
		READY=$(oc get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
		if [ "$READY" = "True" ]; then
			echo "✅ $issuer is ready"
		else
			log_warn "$issuer is not ready (Status: $READY)"
		fi
	done
else
	log_warn "No DNS-01 ClusterIssuers found"
fi

echo

# Check for active DNS-01 challenges
log_info "Checking for active DNS-01 challenges..."
CHALLENGES=$(oc get challenge -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.solver.dns01 != null) | "\(.metadata.namespace)/\(.metadata.name)"' || echo "")

if [ -n "$CHALLENGES" ]; then
	echo "Found DNS-01 challenges:"
	echo

	for challenge in $CHALLENGES; do
		NAMESPACE=$(echo "$challenge" | cut -d'/' -f1)
		NAME=$(echo "$challenge" | cut -d'/' -f2)

		log_debug "Challenge: $NAME (namespace: $NAMESPACE)"

		STATE=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.status.state}' 2>/dev/null || echo "unknown")
		log_debug "  State: $STATE"

		# Get challenge details
		DOMAIN=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.spec.dnsName}' 2>/dev/null || echo "unknown")
		KEY=$(oc get challenge "$NAME" -n "$NAMESPACE" -o jsonpath='{.spec.key}' 2>/dev/null || echo "unknown")

		log_debug "  Domain: $DOMAIN"
		log_debug "  DNS Record: _acme-challenge.$DOMAIN"

		# Check if TXT record should exist
		if [ "$STATE" = "pending" ] || [ "$STATE" = "processing" ]; then
			log_debug "  Expected TXT record key: ${KEY:0:20}..."
		fi

		echo
	done
else
	log_info "No active DNS-01 challenges found"
fi

echo

# Check RFC2136 credentials secret
log_info "Checking RFC2136 credentials..."
if oc get secret rfc2136-credentials -n cert-manager &>/dev/null; then
	echo "✅ RFC2136 credentials secret exists"
else
	log_warn "RFC2136 credentials secret not found in cert-manager namespace"
fi

print_header "Recent cert-manager Logs"
oc logs -n cert-manager deployment/cert-manager --tail=20 2>/dev/null || log_warn "Could not fetch logs"

print_header "Recent Pebble Logs"
oc logs -n pebble -l app=pebble --tail=20 2>/dev/null || log_warn "Could not fetch Pebble logs"

print_header "Recent Fake DNS API Logs"
oc logs -n fake-dns -l app=fake-dns-api --tail=20 2>/dev/null || log_warn "Could not fetch fake DNS API logs"

print_header "Recommendations"
echo "1. For air-gapped DNS-01 testing, ensure Pebble has ALWAYS_VALID=1:"
echo "   PEBBLE_ALWAYS_VALID=1 make test-dns01"
echo
echo "2. Check DNS-01 issuer configuration:"
echo "   ./scripts/troubleshooting/check-issuer.sh pebble-dns01-issuer"
echo
echo "3. Check specific certificate:"
echo "   ./scripts/troubleshooting/check-certificate.sh <cert-name> <namespace>"
echo
echo "4. View fake DNS API logs:"
echo "   oc logs -n fake-dns -l app=fake-dns-api -f"
echo
echo "5. View Pebble challenge test server logs:"
echo "   oc logs -n pebble -l app=pebble-challtestsrv -f"
echo
