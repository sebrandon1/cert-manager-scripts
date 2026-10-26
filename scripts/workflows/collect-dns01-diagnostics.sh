#!/bin/bash

################################################################################
# Script: collect-dns01-diagnostics.sh
# Description: Collect DNS-01 test diagnostics for CI failure analysis
# Used by: reusable-integration-test.yml (on retry and on final failure)
#
# Best-effort: every command is guarded so it is safe when cluster auth or the
# API is degraded, and the script always exits 0 so it cannot mask the real
# failure. kube_timed bounds each API call so a saturated API server cannot
# stall collection for minutes.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0
load_env

CERT_NAMESPACE="${CERT_NAMESPACE:-default}"
CERT_NAME="${CERT_NAME:-wildcard-test}"
FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"
PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"

CERT_MANAGER_NAMESPACE="cert-manager"
OPERATOR_NAMESPACE="cert-manager-operator"

# Dump pod list, per-pod describe, last termination reason and logs (current
# and previous) for a namespace, listing the pods only once.
dump_namespace_pods() {
	local ns="$1"
	local pods pod

	pods=$(kube_timed get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
	kube_timed get pods -n "$ns" -o wide 2>&1 || true
	echo

	while IFS= read -r pod; do
		[[ -z "$pod" ]] && continue
		echo "--- describe pod/$pod ---"
		kube_timed describe pod "$pod" -n "$ns" 2>&1 || true
		echo "--- pod/$pod lastState.terminated.reason ---"
		kube_timed get pod "$pod" -n "$ns" \
			-o jsonpath='{range .status.containerStatuses[*]}{.name}: {.lastState.terminated.reason}{"\n"}{end}' 2>&1 || true
		echo "--- pod/$pod logs (previous) ---"
		kube_timed logs "$pod" -n "$ns" --all-containers=true --previous --tail=200 2>&1 || true
		echo "--- pod/$pod logs (current) ---"
		kube_timed logs "$pod" -n "$ns" --all-containers=true --tail=200 2>&1 || true
		echo
	done <<<"$pods"
}

# Dump every order and challenge in a namespace
dump_acme_objects() {
	local ns="$1"
	local obj name

	for obj in order challenge; do
		echo "=== ${obj}s in namespace $ns ==="
		local names
		names=$(kube_timed get "$obj" -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
		while IFS= read -r name; do
			[[ -z "$name" ]] && continue
			echo "--- describe $obj/$name ---"
			kube_timed describe "$obj" "$name" -n "$ns" 2>&1 || true
			echo "--- $obj/$name yaml ---"
			kube_timed get "$obj" "$name" -n "$ns" -o yaml 2>&1 || true
			echo
		done <<<"$names"
	done
}

print_header "DNS-01 Diagnostics Collection"

################################################################################
# 1. Node health and pressure
################################################################################
print_header "Nodes"
kube_timed whoami 2>&1 || true
kube_timed version --client 2>&1 || true
echo
kube_timed get nodes -o wide 2>&1 || true
echo
echo "=== Node pressure conditions ==="
node_pressure_conditions
echo
echo "=== oc adm top nodes ==="
kube_timed adm top nodes 2>&1 || true
echo
echo "=== oc adm top pods -A ==="
kube_timed adm top pods -A 2>&1 || true
echo

################################################################################
# 2. Certificate / Order / Challenge state
################################################################################
print_header "Certificate and ACME objects ($CERT_NAMESPACE)"
echo "=== certificate $CERT_NAME ==="
kube_timed describe certificate "$CERT_NAME" -n "$CERT_NAMESPACE" 2>&1 || true
echo
kube_timed get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" -o yaml 2>&1 || true
echo
dump_acme_objects "$CERT_NAMESPACE"

################################################################################
# 3. cert-manager controller, webhook and operator
################################################################################
print_header "cert-manager ($CERT_MANAGER_NAMESPACE)"
dump_namespace_pods "$CERT_MANAGER_NAMESPACE"

print_header "cert-manager operator ($OPERATOR_NAMESPACE)"
dump_namespace_pods "$OPERATOR_NAMESPACE"

################################################################################
# 4. fake-dns and Pebble
################################################################################
print_header "fake-dns ($FAKEDNS_NAMESPACE)"
kube_timed describe deployment fake-dns-api -n "$FAKEDNS_NAMESPACE" 2>&1 || true
echo
dump_namespace_pods "$FAKEDNS_NAMESPACE"

print_header "Pebble ($PEBBLE_NAMESPACE)"
kube_timed describe deployment pebble -n "$PEBBLE_NAMESPACE" 2>&1 || true
echo
dump_namespace_pods "$PEBBLE_NAMESPACE"

################################################################################
# 5. DNS path (operator config + CoreDNS)
################################################################################
print_header "DNS configuration"
if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
	echo "=== dns.operator.openshift.io/default ==="
	kube_timed get dns.operator.openshift.io/default -o yaml 2>&1 || true
	echo
	echo "=== dns-default Corefile ==="
	kube_timed get configmap dns-default -n openshift-dns -o jsonpath='{.data.Corefile}' 2>&1 || true
	echo
else
	echo "=== coredns Corefile ==="
	kube_timed get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>&1 || true
	echo
fi
echo "=== fake-dns service ==="
kube_timed get service fake-dns-api -n "$FAKEDNS_NAMESPACE" -o wide 2>&1 || true
echo

################################################################################
# 6. Events and cluster operators
################################################################################
print_header "Recent events (all namespaces)"
kube_timed get events -A --sort-by='.lastTimestamp' 2>&1 | tail -100 || true
echo

if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
	print_header "Cluster operators"
	kube_timed get clusteroperators 2>&1 || true
	echo
	echo "=== DEGRADED / PROGRESSING / UNAVAILABLE operators ==="
	kube_timed get clusteroperators -o jsonpath='{range .items[*]}{.metadata.name}{"\tAvailable="}{.status.conditions[?(@.type=="Available")].status}{"\tProgressing="}{.status.conditions[?(@.type=="Progressing")].status}{"\tDegraded="}{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}' 2>&1 || true
	echo
fi

print_header "DNS-01 Diagnostics Collection Complete"
echo

exit 0
