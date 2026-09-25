#!/bin/bash

################################################################################
# Script: install-ibu-prereqs-with-retry.sh
# Description: Retry IBU prerequisite installation once after cluster recovery
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_DIR/lib/common.sh"
check_help "$@" && exit 0

show_cluster_diagnostics() {
	log_error "--- Cluster diagnostics after IBU prerequisite failure ---"
	"$KUBE_CLI" get nodes -o wide 2>/dev/null || true
	if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
		"$KUBE_CLI" get clusteroperators 2>/dev/null || true
	fi
	"$KUBE_CLI" get pods -n minio -o wide 2>/dev/null || true
	"$KUBE_CLI" get pods -n openshift-adp -o wide 2>/dev/null || true
	"$KUBE_CLI" get events -A --sort-by='.lastTimestamp' 2>/dev/null | tail -50 || true
	log_error "--- End cluster diagnostics ---"
}

main() {
	require_cmd make "$KUBE_CLI"

	log_info "Installing IBU prerequisites (attempt 1 of 2)..."
	if make -C "$REPO_DIR" install-ibu-prereqs; then
		return 0
	else
		local first_status=$?
	fi

	log_warn "IBU prerequisite installation failed (exit $first_status). Attempting cluster recovery before one retry."
	if ! "$SCRIPT_DIR/recover-cluster.sh"; then
		log_warn "Cluster recovery check did not complete successfully; checking API access before deciding whether to retry."
	fi

	if ! "$SCRIPT_DIR/verify-cluster-access.sh"; then
		log_error "Cluster access is still unavailable after recovery; IBU prerequisites will not be retried."
		show_cluster_diagnostics
		return 1
	fi

	log_info "Cluster access is restored. Retrying IBU prerequisite installation once..."
	if make -C "$REPO_DIR" install-ibu-prereqs; then
		log_success "IBU prerequisites installed on the second attempt."
		return 0
	else
		local retry_status=$?
	fi

	log_error "IBU prerequisite installation failed on both attempts."
	if ! "$KUBE_CLI" get nodes &>/dev/null; then
		log_error "Cluster access was lost again during the retry."
		show_cluster_diagnostics
	fi
	return "$retry_status"
}

main "$@"
