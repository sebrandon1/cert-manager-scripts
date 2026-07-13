#!/bin/bash

################################################################################
# Script: create-dns01-issuer.sh
# Description: Create DNS-01 ClusterIssuer for Pebble (with ALWAYS_VALID)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/issuers"

export ISSUER_NAME="${ISSUER_NAME:-pebble-dns01-issuer}"
export ACME_SERVER_URL="${ACME_SERVER_URL:-https://pebble.pebble.svc.cluster.local:14000/dir}"
export ACME_EMAIL="${ACME_EMAIL:-test@example.com}"
export DNS_SERVER="${DNS_SERVER:-8.8.8.8:53}"

print_header "Create DNS-01 ClusterIssuer"

require_cluster

log_info "Creating dummy RFC2136 secret in cert-manager namespace..."
oc create secret generic rfc2136-credentials \
	--from-literal=tsig-secret="$(echo -n "dummy-secret-key" | base64)" \
	--namespace cert-manager \
	--dry-run=client -o yaml | oc apply -f -

apply_yaml_template "$YAML_DIR/pebble-dns01-simple-clusterissuer.yaml" "DNS-01 ClusterIssuer"

log_info "Waiting for ClusterIssuer to be ready..."
retry 3 5 oc wait --for=condition=Ready clusterissuer/"$ISSUER_NAME" --timeout=10s 2>/dev/null

if oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
	oc get clusterissuer "$ISSUER_NAME"
	echo
	log_info "DNS-01 ClusterIssuer created!"
	echo
	print_header "DNS-01 Validation Flow"
	echo "When you create a wildcard certificate:"
	echo
	echo "✅ cert-manager requests a certificate from Pebble"
	echo "✅ Pebble provides a DNS challenge token"
	echo "✅ cert-manager creates a TXT record via the fake DNS API"
	echo "✅ Pebble validates by querying the DNS record"
	echo "✅ Certificate is issued upon successful validation"
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
