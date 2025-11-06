#!/bin/bash

################################################################################
# Script: install-pebble-challtestsrv.sh
# Description: Install Pebble Challenge Test Server for DNS-01 testing
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/../yaml/pebble-challtestsrv"

export PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_note() { echo -e "${BLUE}[NOTE]${NC} $1"; }

echo
echo "========================================"
echo "  Install Pebble Challenge Test Server"
echo "========================================"
echo

# Check prerequisites
if ! command -v oc &>/dev/null; then
	log_error "oc command not found"
	exit 1
fi

if ! oc whoami &>/dev/null; then
	log_error "Not logged into OpenShift"
	exit 1
fi

# Check if Pebble namespace exists
if ! oc get namespace "$PEBBLE_NAMESPACE" &>/dev/null; then
	log_error "Pebble namespace '$PEBBLE_NAMESPACE' not found. Install Pebble first."
	exit 1
fi

log_info "Installing Challenge Test Server..."

# Apply manifests
log_info "Applying deployment..."
envsubst <"$YAML_DIR/deployment.yaml" | oc apply -f -

log_info "Applying service..."
envsubst <"$YAML_DIR/service.yaml" | oc apply -f -

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
log_note "This DNS server works with Pebble's ALWAYS_VALID mode!"
