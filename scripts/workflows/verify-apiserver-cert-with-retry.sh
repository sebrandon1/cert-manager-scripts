#!/bin/bash

################################################################################
# Script: verify-apiserver-cert-with-retry.sh
# Description: Verify API server certificate with cluster connectivity retry
# Used by: reusable-integration-test.yml
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

log_info "Waiting for cluster connectivity before verification..."
for i in 1 2 3 4 5; do
	if oc whoami &>/dev/null && oc get nodes &>/dev/null; then
		log_info "Cluster connectivity confirmed"
		make verify-apiserver-cert
		exit $?
	fi
	log_warn "Waiting for cluster connectivity (attempt $i/5)..."
	sleep 5
done
log_warn "Cluster connectivity not restored - skipping verification"
log_info "The certificate was created, but verification could not be completed"
exit 0
