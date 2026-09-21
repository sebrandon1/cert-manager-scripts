#!/bin/bash

################################################################################
# Script: check-expiry.sh
# Description: List all Certificates and highlight those expiring within a window
#
# Environment:
#   EXPIRY_DAYS  Days until expiry to treat as WARN (default: 30)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0
load_env

EXPIRY_DAYS="${EXPIRY_DAYS:-30}"

require_cmd "$KUBE_CLI" jq
require_cluster

print_header "Certificate Expiry Check (window: ${EXPIRY_DAYS} days)"

all_certs_json=$("$KUBE_CLI" get certificate -A -o json 2>/dev/null || echo '{"items":[]}')
cert_count=$(echo "$all_certs_json" | jq '.items | length')

if [ "$cert_count" -eq 0 ]; then
	log_info "No certificates found in any namespace"
	exit 0
fi

log_info "Found $cert_count certificate(s)"
echo

printf "  %-30s %-20s %-8s %-25s %-10s %-10s\n" \
	"NAME" "NAMESPACE" "READY" "NOT AFTER" "DAYS LEFT" "STATUS"
printf "  %-30s %-20s %-8s %-25s %-10s %-10s\n" \
	"────" "─────────" "─────" "─────────" "─────────" "──────"

issues=0
now_epoch=$(date +%s)

while IFS= read -r cert_json; do
	[ -z "$cert_json" ] && continue

	local_name=$(echo "$cert_json" | jq -r '.metadata.name')
	local_ns=$(echo "$cert_json" | jq -r '.metadata.namespace')
	ready=$(echo "$cert_json" | jq -r '(.status.conditions[]? | select(.type=="Ready") | .status) // "Unknown"')
	not_after=$(echo "$cert_json" | jq -r '.status.notAfter // empty')

	days_left="N/A"
	status="UNKNOWN"

	if [ -n "$not_after" ]; then
		expiry_epoch=$(parse_date_to_epoch "$not_after")
		if [ -n "$expiry_epoch" ]; then
			days_left=$(((expiry_epoch - now_epoch) / 86400))
			if [ "$days_left" -le 0 ]; then
				status="EXPIRED"
				issues=$((issues + 1))
			elif [ "$days_left" -le "$EXPIRY_DAYS" ]; then
				status="WARN"
				issues=$((issues + 1))
			else
				status="OK"
			fi
		fi
	fi

	printf "  %-30s %-20s %-8s %-25s %-10s %-10s\n" \
		"$local_name" "$local_ns" "$ready" "${not_after:-n/a}" "$days_left" "$status"
done < <(echo "$all_certs_json" | jq -c '.items[]')

echo
if [ "$issues" -gt 0 ]; then
	log_error "$issues certificate(s) expired or expiring within ${EXPIRY_DAYS} days"
	exit 1
fi

log_success "All certificates are outside the ${EXPIRY_DAYS}-day expiry window"
exit 0
