#!/bin/bash

################################################################################
# Script: validate-post-restore.sh
# Description: Validate cluster health after IBU backup/restore simulation
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"

pass_count=0
fail_count=0

record_pass() {
	log_success "$1"
	pass_count=$((pass_count + 1))
}

record_fail() {
	log_error "$1"
	fail_count=$((fail_count + 1))
}

check_node_readiness() {
	local nodes_json
	nodes_json=$("$KUBE_CLI" get nodes -o json 2>/dev/null) || {
		record_fail "Cannot retrieve node status"
		return
	}

	local not_ready
	not_ready=$(echo "$nodes_json" | jq -r \
		'.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | .metadata.name' 2>/dev/null || echo "")

	if [ -z "$not_ready" ]; then
		local node_count
		node_count=$(echo "$nodes_json" | jq '.items | length')
		record_pass "All $node_count node(s) are Ready"
	else
		record_fail "Not-ready nodes: $not_ready"
	fi
}

check_cert_manager() {
	if check_deployment_exists cert-manager "$CERT_MANAGER_NAMESPACE"; then
		record_pass "cert-manager controller is running"
	else
		record_fail "cert-manager controller is not running"
	fi

	if check_deployment_exists cert-manager-webhook "$CERT_MANAGER_NAMESPACE"; then
		record_pass "cert-manager webhook is running"
	else
		record_fail "cert-manager webhook is not running"
	fi
}

check_system_pods() {
	if [[ "${CLUSTER_TYPE:-}" != "openshift" ]]; then
		return
	fi

	local checks=(
		"openshift-apiserver:app=openshift-apiserver:OpenShift API server"
		"openshift-controller-manager:app=controller-manager:OpenShift controller manager"
	)

	for check in "${checks[@]}"; do
		local namespace label description
		IFS=: read -r namespace label description <<<"$check"
		local pod_count
		pod_count=$("$KUBE_CLI" get pods -n "$namespace" -l "$label" \
			--field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)
		if [ "$pod_count" -gt 0 ]; then
			record_pass "$description pods running ($pod_count)"
		else
			record_fail "$description pods not running"
		fi
	done
}

check_cluster_operators() {
	if [[ "${CLUSTER_TYPE:-}" != "openshift" ]]; then
		return
	fi

	local degraded
	degraded=$("$KUBE_CLI" get clusteroperators -o json 2>/dev/null |
		jq -r '.items[] | select(.status.conditions[]? | select(.type=="Degraded" and .status=="True")) | .metadata.name' 2>/dev/null || echo "")

	if [ -z "$degraded" ]; then
		record_pass "No degraded ClusterOperators"
	else
		record_fail "Degraded ClusterOperators: $degraded"
	fi
}

require_cmd jq
require_cluster

print_header "Post-Restore Cluster Validation"
echo

check_node_readiness
check_cert_manager
check_system_pods
check_cluster_operators

echo
print_summary \
	"Passed" "$pass_count" \
	"Failed" "$fail_count" \
	"Total" "$((pass_count + fail_count))"

if [ "$fail_count" -gt 0 ]; then
	echo
	log_warn "Some post-restore checks failed. The cluster may need manual intervention."
	exit 1
else
	echo
	log_success "Cluster is healthy after restore."
fi
