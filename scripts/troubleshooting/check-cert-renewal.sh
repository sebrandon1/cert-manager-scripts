#!/bin/bash

################################################################################
# Script: check-cert-renewal.sh
# Description: Check certificate renewal status and upcoming renewals
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

parse_date_to_epoch() {
	local datestr="$1"
	date -jf "%Y-%m-%dT%H:%M:%SZ" "$datestr" +%s 2>/dev/null ||
		date -d "$datestr" +%s 2>/dev/null || echo ""
}

check_single_certificate() {
	local cert_json="$1"
	local cert_name namespace ready not_after renewal_time

	cert_name=$(echo "$cert_json" | jq -r '.metadata.name')
	namespace=$(echo "$cert_json" | jq -r '.metadata.namespace')
	ready=$(echo "$cert_json" | jq -r '(.status.conditions[]? | select(.type=="Ready") | .status) // "Unknown"')
	not_after=$(echo "$cert_json" | jq -r '.status.notAfter // empty')
	renewal_time=$(echo "$cert_json" | jq -r '.status.renewalTime // empty')

	local now_epoch days_until_expiry days_until_renewal status_label
	now_epoch=$(date +%s)

	if [ -n "$not_after" ]; then
		local expiry_epoch
		expiry_epoch=$(parse_date_to_epoch "$not_after")
		if [ -n "$expiry_epoch" ]; then
			days_until_expiry=$(((expiry_epoch - now_epoch) / 86400))
		else
			days_until_expiry="N/A"
		fi
	else
		days_until_expiry="N/A"
	fi

	if [ -n "$renewal_time" ]; then
		local renewal_epoch
		renewal_epoch=$(parse_date_to_epoch "$renewal_time")
		if [ -n "$renewal_epoch" ]; then
			days_until_renewal=$(((renewal_epoch - now_epoch) / 86400))
		else
			days_until_renewal="N/A"
		fi
	else
		days_until_renewal="N/A"
	fi

	if [ "$ready" != "True" ]; then
		status_label="NOT READY"
	elif [ "$days_until_expiry" != "N/A" ] && [ "$days_until_expiry" -le 0 ]; then
		status_label="EXPIRED"
	elif [ "$days_until_renewal" != "N/A" ] && [ "$days_until_renewal" -le 0 ]; then
		status_label="RENEWING"
	elif [ "$days_until_expiry" != "N/A" ] && [ "$days_until_expiry" -le 7 ]; then
		status_label="EXPIRING SOON"
	else
		status_label="OK"
	fi

	printf "  %-30s %-15s %-10s %-12s %-12s %-15s\n" \
		"$cert_name" "$namespace" "$ready" "$days_until_expiry" "$days_until_renewal" "$status_label"
}

check_renewal_details() {
	local cert_name="$1"
	local namespace="$2"

	local cert_json
	cert_json=$("$KUBE_CLI" get certificate "$cert_name" -n "$namespace" -o json 2>/dev/null) || {
		log_error "Certificate '$cert_name' not found in namespace '$namespace'"
		exit 1
	}

	print_header "Renewal Details: $cert_name ($namespace)"

	local duration renew_before renewal_time not_after not_before
	duration=$(echo "$cert_json" | jq -r '.spec.duration // "not set"')
	renew_before=$(echo "$cert_json" | jq -r '.spec.renewBefore // "not set"')
	renewal_time=$(echo "$cert_json" | jq -r '.status.renewalTime // "not set"')
	not_after=$(echo "$cert_json" | jq -r '.status.notAfter // "not set"')
	not_before=$(echo "$cert_json" | jq -r '.status.notBefore // "not set"')

	print_summary \
		"Certificate" "$cert_name" \
		"Namespace" "$namespace" \
		"Duration" "$duration" \
		"Renew Before" "$renew_before" \
		"Not Before" "$not_before" \
		"Not After (Expiry)" "$not_after" \
		"Renewal Time" "$renewal_time"

	echo

	local cr_json
	cr_json=$("$KUBE_CLI" get certificaterequest -n "$namespace" -o json 2>/dev/null || echo '{"items":[]}')

	local cr_list
	cr_list=$(echo "$cr_json" | jq -r \
		".items[] | select(.metadata.ownerReferences[]?.name==\"$cert_name\") | \
		\"\(.metadata.name) \((.status.conditions[]? | select(.type==\"Ready\") | .status) // \"Unknown\") \((.status.conditions[]? | select(.type==\"Ready\") | .reason) // \"\")\"" 2>/dev/null || echo "")

	if [ -n "$cr_list" ]; then
		log_info "Active CertificateRequests:"
		while read -r cr cr_ready cr_reason; do
			[ -z "$cr" ] && continue
			echo "    $cr (Ready: $cr_ready, Reason: $cr_reason)"
		done <<<"$cr_list"
	else
		log_info "No active CertificateRequests found"
	fi
	echo
}

require_cmd "$KUBE_CLI" jq
require_cluster

if [ $# -eq 0 ]; then
	print_header "Certificate Renewal Status"

	all_certs_json=$("$KUBE_CLI" get certificate -A -o json 2>/dev/null || echo '{"items":[]}')

	cert_count=$(echo "$all_certs_json" | jq '.items | length')

	if [ "$cert_count" -eq 0 ]; then
		log_warn "No certificates found in any namespace"
		exit 0
	fi

	log_info "Found $cert_count certificate(s)"
	echo

	printf "  %-30s %-15s %-10s %-12s %-12s %-15s\n" \
		"CERTIFICATE" "NAMESPACE" "READY" "DAYS LEFT" "RENEW IN" "STATUS"
	printf "  %-30s %-15s %-10s %-12s %-12s %-15s\n" \
		"───────────" "─────────" "─────" "─────────" "────────" "──────"

	echo "$all_certs_json" | jq -c '.items[]' | while IFS= read -r cert_json; do
		check_single_certificate "$cert_json"
	done

	echo
elif [ $# -eq 2 ]; then
	check_renewal_details "$1" "$2"
else
	echo "Usage: $0 [<certificate-name> <namespace>]"
	echo
	echo "Examples:"
	echo "  $0                              # Check all certificates"
	echo "  $0 test-cert-simple default     # Check specific certificate"
	exit 1
fi
