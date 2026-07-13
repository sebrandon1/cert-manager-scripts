#!/bin/bash

################################################################################
# Script: verify-key-formats.sh
# Description: Verify PEM key formats of all TLS secrets in a namespace.
#              Reports the PEM header type for each secret's tls.key field.
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
setup_cleanup

# Configuration
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc jq
	require_cluster
	log_success "Prerequisites met."
}

verify_all_key_formats() {
	print_header "TLS Secret Key Formats - Namespace: $TARGET_NAMESPACE"

	local tmp_file
	tmp_file=$(mktemp)
	register_temp_file "$tmp_file"

	capture_secret_checksums "$TARGET_NAMESPACE" "$tmp_file"

	local count
	count=$(jq 'length' "$tmp_file")

	if [ "$count" -eq 0 ]; then
		log_warn "No TLS secrets found in namespace '$TARGET_NAMESPACE'."
		return 0
	fi

	printf "  %-40s %s\n" "SECRET NAME" "PEM TYPE"
	printf "  %-40s %s\n" "───────────" "────────"

	local sec1_count=0
	local pkcs1_count=0
	local pkcs8_count=0
	local unknown_count=0

	while IFS=$'\t' read -r name pem_type; do
		printf "  %-40s %s\n" "$name" "$pem_type"

		case "$pem_type" in
		"EC PRIVATE KEY") sec1_count=$((sec1_count + 1)) ;;
		"RSA PRIVATE KEY") pkcs1_count=$((pkcs1_count + 1)) ;;
		"PRIVATE KEY") pkcs8_count=$((pkcs8_count + 1)) ;;
		*) unknown_count=$((unknown_count + 1)) ;;
		esac
	done < <(jq -r '.[] | [.name, .pem_type] | @tsv' "$tmp_file")

	echo
	print_summary \
		"Total TLS Secrets" "$count" \
		"EC PRIVATE KEY (SEC1)" "$sec1_count" \
		"RSA PRIVATE KEY (PKCS#1)" "$pkcs1_count" \
		"PRIVATE KEY (PKCS#8)" "$pkcs8_count" \
		"UNKNOWN" "$unknown_count"
}

main() {
	check_prerequisites
	verify_all_key_formats
}

main "$@"
