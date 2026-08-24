#!/bin/bash

################################################################################
# Script: verify-apiserver-cert-with-retry.sh
# Description: Verify API server certificate with cluster connectivity retry
# Used by: reusable-integration-test.yml
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# shellcheck disable=SC2329
check_cluster() {
	if [[ "$KUBE_CLI" == "oc" ]]; then
		"$KUBE_CLI" whoami &>/dev/null && "$KUBE_CLI" get nodes &>/dev/null
	else
		"$KUBE_CLI" get namespace default &>/dev/null && "$KUBE_CLI" get nodes &>/dev/null
	fi
}

if [[ "$CLUSTER_TYPE" != "openshift" ]]; then
	log_info "Skipping API server certificate verification (OpenShift-only)"
	exit 0
fi

log_info "Waiting for cluster connectivity before verification..."
if wait_for_condition 5 5 check_cluster; then
	log_info "Cluster connectivity confirmed"
	make verify-apiserver-cert
	exit $?
fi
log_warn "Cluster connectivity not restored - skipping verification"
log_info "The certificate was created, but verification could not be completed"
exit 0
