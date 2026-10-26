#!/bin/bash

################################################################################
# Script: reset-dns01-state.sh
# Description: Best-effort reset of DNS-01 test state between CI retry attempts
# Used by: reusable-integration-test.yml (on_retry_command)
#
# Deletes the test namespace's cert-manager ACME objects and any stuck
# fake-dns / Pebble pods, then reports cluster and node health. It deliberately
# avoids `make clean-fake-dns`/`clean-pebble`: clean-fake-dns removes the DNS
# operator patch, and re-installing is the expensive, churn-heavy path.
#
# ALWAYS exits 0 so it cannot mask the real failure.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0
load_env

CERT_NAMESPACE="${CERT_NAMESPACE:-default}"
CERT_NAME="${CERT_NAME:-wildcard-test}"
CERT_SECRET_NAME="${CERT_SECRET_NAME:-wildcard-test-tls}"
FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"
PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"

# Delete stuck pods in a namespace, but only if the deployment has no available
# replica (never remove the last healthy pod).
recover_stuck_pods() {
	local ns="$1" deployment="$2"
	local stuck pod
	stuck=$(unhealthy_pods "$ns")
	if [[ -z "$stuck" ]]; then
		log_info "No stuck pods in $ns"
		return 0
	fi

	if deployment_has_available_replica "$deployment" "$ns"; then
		log_info "$ns: deployment $deployment has a healthy replica; not deleting pods"
		log_info "  Stuck pods: $(echo "$stuck" | tr '\n' ' ')"
		return 0
	fi

	log_warn "$ns: deployment $deployment has no available replica; deleting stuck pods"
	while IFS= read -r pod; do
		[[ -z "$pod" ]] && continue
		log_info "  Deleting pod/$pod"
		kube_timed delete pod "$pod" -n "$ns" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
	done <<<"$stuck"
}

print_header "Reset DNS-01 Test State"

################################################################################
# 1. Delete the test namespace's cert-manager ACME state
################################################################################
log_info "Deleting certificate/$CERT_NAME and its ACME objects in $CERT_NAMESPACE..."
kube_timed delete certificate "$CERT_NAME" -n "$CERT_NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null || true

for obj in certificaterequest order challenge; do
	names=$(kube_timed get "$obj" -n "$CERT_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
	while IFS= read -r name; do
		[[ -z "$name" ]] && continue
		log_info "  Deleting $obj/$name"
		kube_timed delete "$obj" "$name" -n "$CERT_NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
	done <<<"$names"
done

kube_timed delete secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null || true
echo

################################################################################
# 2. Recover stuck fake-dns / Pebble pods (without reinstalling)
################################################################################
recover_stuck_pods "$FAKEDNS_NAMESPACE" fake-dns-api
recover_stuck_pods "$PEBBLE_NAMESPACE" pebble
echo

################################################################################
# 3. Cluster and node health (informational only)
################################################################################
log_info "Node pressure conditions:"
node_pressure_conditions
echo

if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
	log_info "Cluster operators not Available or currently Degraded:"
	kube_timed get clusteroperators -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Available")].status}{"\t"}{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}' 2>/dev/null |
		awk -F'\t' '$2 != "True" || $3 == "True"' || true
	echo
fi

################################################################################
# 4. Let deleted objects (which have finalizers) and pod GC settle
################################################################################
log_info "Waiting 20s for pod garbage collection to settle..."
sleep 20

log_success "DNS-01 state reset complete"
echo

exit 0
