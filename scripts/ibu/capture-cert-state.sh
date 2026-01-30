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

# Configuration
STATE_DIR="${STATE_DIR:-/tmp/ibu-cert-state}"
STATE_LABEL="${STATE_LABEL:-before}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"

print_header() {
	echo
	echo "========================================"
	echo "  Certificate State Capture"
	echo "  Label: $STATE_LABEL"
	echo "========================================"
	echo
}

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

	# Compute SHA256 checksums for each TLS secret's certificate data
	echo "[]" >"$checksums_file"

	# shellcheck disable=SC2016
	local secret_names
	secret_names=$(oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq -r '
		.items | map(select(.type == "kubernetes.io/tls" or (.data["tls.crt"] != null))) | .[].metadata.name
	')

	for secret_name in $secret_names; do
		# Get the certificate data and compute checksum
		local cert_data
		cert_data=$(oc get secret "$secret_name" -n "$TARGET_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")

		if [ -n "$cert_data" ]; then
			local checksum
			checksum=$(echo "$cert_data" | shasum -a 256 | cut -d' ' -f1)

			# Also capture key checksum
			local key_data
			key_data=$(oc get secret "$secret_name" -n "$TARGET_NAMESPACE" -o jsonpath='{.data.tls\.key}' 2>/dev/null || echo "")
			local key_checksum=""
			if [ -n "$key_data" ]; then
				key_checksum=$(echo "$key_data" | shasum -a 256 | cut -d' ' -f1)
			fi

			# Add to checksums file
			jq --arg name "$secret_name" \
				--arg cert_checksum "$checksum" \
				--arg key_checksum "$key_checksum" \
				'. += [{name: $name, cert_checksum: $cert_checksum, key_checksum: $key_checksum}]' \
				"$checksums_file" >"$checksums_file.tmp" && mv "$checksums_file.tmp" "$checksums_file"
		fi
	done

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

print_summary() {
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  State Capture Summary ($STATE_LABEL)"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo

	local cert_count
	cert_count=$(jq 'length' "$STATE_DIR/certificates-${STATE_LABEL}.json" 2>/dev/null || echo "0")
	echo "  Certificates:     $cert_count"

	local secret_count
	secret_count=$(jq 'length' "$STATE_DIR/checksums-${STATE_LABEL}.json" 2>/dev/null || echo "0")
	echo "  TLS Secrets:      $secret_count"

	local issuer_count
	issuer_count=$(jq 'length' "$STATE_DIR/issuers-${STATE_LABEL}.json" 2>/dev/null || echo "0")
	echo "  ClusterIssuers:   $issuer_count"

	echo
	echo "  State saved to:   $STATE_DIR"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
}

main() {
	print_header
	check_prerequisites
	setup_state_directory

	capture_certificates
	capture_secrets
	capture_issuers
	capture_metadata

	print_summary
	log_success "State capture complete!"
}

main
