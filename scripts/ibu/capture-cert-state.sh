#!/bin/bash

################################################################################
# Script: capture-cert-state.sh
# Description: Capture current state of certificates, secrets, and issuers
#              for before/after comparison in IBU testing
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
setup_cleanup

# Configuration
STATE_DIR="${STATE_DIR:?STATE_DIR must be set by the calling script}"
STATE_LABEL="${STATE_LABEL:-before}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc jq
	require_cluster
	log_info "Prerequisites check passed."
}

setup_state_directory() {
	log_info "Setting up state directory..."
	mkdir -p "$STATE_DIR"
	log_info "State will be saved to: $STATE_DIR"
}

capture_certificates() {
	log_info "Capturing certificates in namespace $TARGET_NAMESPACE..."

	local cert_file="$STATE_DIR/certificates-${STATE_LABEL}.json"

	# Get all certificates with full details
	oc get certificates -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '
		.items | map({
			name: .metadata.name,
			namespace: .metadata.namespace,
			secretName: .spec.secretName,
			dnsNames: .spec.dnsNames,
			issuerRef: .spec.issuerRef,
			ready: (.status.conditions // [] | map(select(.type == "Ready")) | .[0].status // "Unknown"),
			notBefore: .status.notBefore,
			notAfter: .status.notAfter,
			renewalTime: .status.renewalTime
		})
	' >"$cert_file"

	local count
	count=$(jq 'length' "$cert_file")
	log_info "Captured $count certificates"
}

capture_secrets() {
	log_info "Capturing TLS secrets in namespace $TARGET_NAMESPACE..."

	local secrets_file="$STATE_DIR/secrets-${STATE_LABEL}.json"
	local checksums_file="$STATE_DIR/checksums-${STATE_LABEL}.json"

	# Get TLS secrets (those containing tls.crt and tls.key)
	oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '
		.items | map(select(.type == "kubernetes.io/tls" or (.data["tls.crt"] != null))) | map({
			name: .metadata.name,
			namespace: .metadata.namespace,
			type: .type,
			creationTimestamp: .metadata.creationTimestamp,
			hasCert: (.data["tls.crt"] != null),
			hasKey: (.data["tls.key"] != null)
		})
	' >"$secrets_file"

	# Capture checksums using shared library function
	capture_secret_checksums "$TARGET_NAMESPACE" "$checksums_file"

	local count
	count=$(jq 'length' "$checksums_file")
	log_info "Captured $count TLS secret checksums"
}

capture_issuers() {
	log_info "Capturing ClusterIssuers..."

	local issuers_file="$STATE_DIR/issuers-${STATE_LABEL}.json"

	oc get clusterissuers -o json 2>/dev/null | jq '
		.items | map({
			name: .metadata.name,
			type: (if .spec.acme then "ACME" elif .spec.ca then "CA" elif .spec.selfSigned then "SelfSigned" else "Other" end),
			ready: (.status.conditions // [] | map(select(.type == "Ready")) | .[0].status // "Unknown")
		})
	' >"$issuers_file"

	local count
	count=$(jq 'length' "$issuers_file")
	log_info "Captured $count ClusterIssuers"

	# Also capture namespace-scoped issuers
	local ns_issuers_file="$STATE_DIR/ns-issuers-${STATE_LABEL}.json"

	oc get issuers -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '
		.items | map({
			name: .metadata.name,
			namespace: .metadata.namespace,
			type: (if .spec.acme then "ACME" elif .spec.ca then "CA" elif .spec.selfSigned then "SelfSigned" else "Other" end),
			ready: (.status.conditions // [] | map(select(.type == "Ready")) | .[0].status // "Unknown")
		})
	' >"$ns_issuers_file" 2>/dev/null || echo "[]" >"$ns_issuers_file"
}

capture_metadata() {
	log_info "Capturing metadata..."

	local metadata_file="$STATE_DIR/metadata-${STATE_LABEL}.json"

	cat >"$metadata_file" <<EOF
{
	"captureTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
	"label": "$STATE_LABEL",
	"namespace": "$TARGET_NAMESPACE",
	"cluster": "$(oc whoami --show-server 2>/dev/null || echo 'unknown')",
	"user": "$(oc whoami 2>/dev/null || echo 'unknown')"
}
EOF
}

print_capture_summary() {
	local cert_count
	cert_count=$(jq 'length' "$STATE_DIR/certificates-${STATE_LABEL}.json" 2>/dev/null || echo "0")

	local secret_count
	secret_count=$(jq 'length' "$STATE_DIR/checksums-${STATE_LABEL}.json" 2>/dev/null || echo "0")

	local issuer_count
	issuer_count=$(jq 'length' "$STATE_DIR/issuers-${STATE_LABEL}.json" 2>/dev/null || echo "0")

	print_summary \
		"State Label" "$STATE_LABEL" \
		"Certificates" "$cert_count" \
		"TLS Secrets" "$secret_count" \
		"ClusterIssuers" "$issuer_count" \
		"State saved to" "$STATE_DIR"
}

main() {
	print_header "Certificate State Capture - Label: $STATE_LABEL"
	check_prerequisites
	setup_state_directory

	capture_certificates
	capture_secrets
	capture_issuers
	capture_metadata

	print_capture_summary
	log_success "State capture complete!"
}

main
