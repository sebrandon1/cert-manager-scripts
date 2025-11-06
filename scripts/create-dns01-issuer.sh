#!/bin/bash

################################################################################
# Script: create-dns01-issuer.sh
# Description: Create DNS-01 ClusterIssuer for Pebble (with ALWAYS_VALID)
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/../yaml/issuers"

# Configuration
export ISSUER_NAME="${ISSUER_NAME:-pebble-dns01-issuer}"
export ACME_SERVER_URL="${ACME_SERVER_URL:-https://pebble.pebble.svc.cluster.local:14000/dir}"
export ACME_EMAIL="${ACME_EMAIL:-test@example.com}"
export DNS_SERVER="${DNS_SERVER:-8.8.8.8:53}"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo
echo "========================================"
echo "  Create DNS-01 ClusterIssuer"
echo "========================================"
echo

# Check prerequisites
if ! oc whoami &>/dev/null; then
	log_error "Not logged into OpenShift"
	exit 1
fi

# Create dummy secret for RFC2136 (not actually used with ALWAYS_VALID)
# Secret must be in cert-manager namespace for ClusterIssuer
# Value must be valid base64
log_info "Creating dummy RFC2136 secret in cert-manager namespace..."
oc create secret generic rfc2136-credentials \
	--from-literal=tsig-secret=$(echo -n "dummy-secret-key" | base64) \
	--namespace cert-manager \
	--dry-run=client -o yaml | oc apply -f -

# Create ClusterIssuer
log_info "Creating DNS-01 ClusterIssuer..."
envsubst <"$YAML_DIR/pebble-dns01-simple-clusterissuer.yaml" | oc apply -f -

log_info "Waiting for ClusterIssuer to be ready..."
sleep 5

if oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
	oc get clusterissuer "$ISSUER_NAME"
	echo
	log_info "DNS-01 ClusterIssuer created!"
	echo
	echo "Next steps:"
	echo "1. Create a wildcard certificate:"
	echo "   oc apply -f - <<EOF"
	echo "   apiVersion: cert-manager.io/v1"
	echo "   kind: Certificate"
	echo "   metadata:"
	echo "     name: wildcard-test"
	echo "     namespace: default"
	echo "   spec:"
	echo "     secretName: wildcard-test-tls"
	echo "     issuerRef:"
	echo "       name: pebble-dns01-issuer"
	echo "       kind: ClusterIssuer"
	echo "     dnsNames:"
	echo "     - '*.example.com'"
	echo "     - 'example.com'"
	echo "   EOF"
	echo
	echo "2. Monitor certificate status:"
	echo "   oc get certificate -n default -w"
fi
