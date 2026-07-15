#!/bin/bash

################################################################################
# Script: install-pebble-challtestsrv.sh
# Description: Install Pebble Challenge Test Server for DNS-01 testing
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

YAML_DIR="${SCRIPT_DIR}/../yaml/pebble-challtestsrv"

export PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"

print_header "Install Pebble Challenge Test Server"

require_cmd oc
require_cluster
require_healthy_cluster

if ! oc get namespace "$PEBBLE_NAMESPACE" &>/dev/null; then
	log_error "Pebble namespace '$PEBBLE_NAMESPACE' not found. Install Pebble first."
	exit 1
fi

log_info "Installing Challenge Test Server..."

apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
apply_yaml_template "$YAML_DIR/service.yaml" "Service"

log_info "Waiting for Challenge Test Server to be ready..."
oc wait --for=condition=available --timeout=120s \
	deployment/pebble-challtestsrv \
	-n "$PEBBLE_NAMESPACE" || {
	log_warn "Deployment not ready yet, checking status..."
	oc get pods -n "$PEBBLE_NAMESPACE" -l app=pebble-challtestsrv
}

log_info "Challenge Test Server is ready!"
echo
log_info "DNS Server: pebble-challtestsrv.${PEBBLE_NAMESPACE}.svc.cluster.local:8053"
log_info "Management API: http://pebble-challtestsrv.${PEBBLE_NAMESPACE}.svc.cluster.local:8055"
echo
echo "Next steps:"
echo "1. Configure Pebble to use this DNS server:"
echo "   Edit Pebble configmap to set DNS_SERVER"
echo
echo "2. Use management API to set DNS records:"
echo "   curl -X POST http://pebble-challtestsrv.pebble.svc:8055/set-txt \\"
echo "     -d '{\"host\":\"_acme-challenge.example.com.\",\"value\":\"test\"}'"
echo
log_info "This DNS server works with Pebble's ALWAYS_VALID mode!"
