#!/bin/bash

################################################################################
# Script: wait-for-cluster-operators.sh
# Description: Poll cluster operators until all are healthy
# Used by: reusable-integration-test.yml
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

check_operators_healthy() {
	local degraded
	degraded=$(oc get clusteroperators --no-headers | awk '($3!="True" || $4=="True" || $5=="True")' | wc -l | xargs)
	[ "$degraded" -eq 0 ]
}

log_info "Waiting for cluster operators to stabilize (up to 10 minutes)..."
if wait_for_condition 60 10 check_operators_healthy; then
	log_success "All cluster operators are healthy!"
else
	log_warn "Timeout waiting for all cluster operators. Checking critical operators..."
fi
log_info "Cluster operator status:"
oc get clusteroperators || true

require_healthy_cluster 30 10
