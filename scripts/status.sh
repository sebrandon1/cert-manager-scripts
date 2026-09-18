#!/bin/bash

################################################################################
# Script: status.sh
# Description: Show installed components with deployment health and replica readiness
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

# Dim text for "Not installed" (common.sh has no DIM)
DIM=''
if [[ -n "$GREEN" ]]; then
	DIM='\033[2m'
fi

# Print Ready/Degraded from "desired ready" replica counts.
# Empty readyReplicas is treated as 0.
print_ready_status() {
	local info="$1"
	local desired ready
	read -r desired ready <<<"$info"
	desired="${desired:-0}"
	ready="${ready:-0}"

	if [[ "$ready" == "$desired" ]] && [[ "$ready" != "0" ]]; then
		echo -e "${GREEN}Ready ${ready}/${desired}${NC}"
	else
		echo -e "${YELLOW}Degraded ${ready}/${desired}${NC}"
	fi
}

# Print one table row for a named deployment.
show_deployment_status() {
	local label="$1"
	local name="$2"
	local namespace="$3"

	printf "  %-25s " "$label"

	local info
	if ! info=$("$KUBE_CLI" get deployment "$name" -n "$namespace" \
		-o jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}' 2>/dev/null) ||
		[[ -z "${info// /}" ]]; then
		echo -e "${DIM}Not installed${NC}"
		return 0
	fi

	print_ready_status "$info"
}

# OADP uses deployment/velero when present, otherwise the velero label selector.
show_oadp_status() {
	printf "  %-25s " "OADP"

	local info
	if info=$("$KUBE_CLI" get deployment velero -n openshift-adp \
		-o jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}' 2>/dev/null) &&
		[[ -n "${info// /}" ]]; then
		print_ready_status "$info"
		return 0
	fi

	info=$("$KUBE_CLI" get deployment -n openshift-adp -l app.kubernetes.io/name=velero \
		-o jsonpath='{.items[0].spec.replicas}{" "}{.items[0].status.readyReplicas}' 2>/dev/null || true)

	if [[ -z "${info// /}" ]]; then
		echo -e "${DIM}Not installed${NC}"
		return 0
	fi

	print_ready_status "$info"
}

print_header "Component Status Dashboard"

printf "  %b%-25s %s%b\n" "$BOLD" "Component" "Status" "$NC"
echo "  ─────────────────────── ──────────────────────────"

show_deployment_status "cert-manager" "cert-manager" "cert-manager"
show_deployment_status "cert-manager-webhook" "cert-manager-webhook" "cert-manager"
show_deployment_status "Pebble ACME server" "pebble" "pebble"
show_deployment_status "Fake DNS API" "fake-dns-api" "fake-dns"
show_deployment_status "acme-dns" "acme-dns" "acme-dns"
show_deployment_status "pebble-challtestsrv" "pebble-challtestsrv" "pebble"
show_deployment_status "MinIO" "minio" "minio"
show_oadp_status

# Parse RFC3339 / ISO8601 timestamps to epoch (macOS date -j and GNU date -d).
parse_date_to_epoch() {
	local datestr="$1"
	date -jf "%Y-%m-%dT%H:%M:%SZ" "$datestr" +%s 2>/dev/null ||
		date -d "$datestr" +%s 2>/dev/null || echo ""
}

# List Certificates with Ready, notAfter, and days remaining.
show_certificates_status() {
	local certs_json count now_epoch
	require_cmd jq

	if ! certs_json=$("$KUBE_CLI" get certificate --all-namespaces -o json 2>/dev/null); then
		echo -e "  ${DIM}No Certificates found${NC}"
		return 0
	fi

	count=$(echo "$certs_json" | jq '.items | length')
	if [[ "$count" -eq 0 ]]; then
		echo -e "  ${DIM}No Certificates found${NC}"
		return 0
	fi

	printf "  %-20s %-30s %-8s %-22s %-6s\n" \
		"NAMESPACE" "NAME" "READY" "NOT_AFTER" "DAYS"
	printf "  %-20s %-30s %-8s %-22s %-6s\n" \
		"─────────" "────" "─────" "─────────" "────"

	now_epoch=$(date +%s)
	echo "$certs_json" | jq -c '.items[]' | while IFS= read -r cert_json; do
		local ns name ready not_after days_str color expiry_epoch days
		ns=$(echo "$cert_json" | jq -r '.metadata.namespace')
		name=$(echo "$cert_json" | jq -r '.metadata.name')
		ready=$(echo "$cert_json" | jq -r '(.status.conditions[]? | select(.type=="Ready") | .status) // "Unknown"')
		not_after=$(echo "$cert_json" | jq -r '.status.notAfter // empty')

		days_str="—"
		color=""
		if [[ -n "$not_after" ]]; then
			expiry_epoch=$(parse_date_to_epoch "$not_after")
			if [[ -n "$expiry_epoch" ]]; then
				days=$(((expiry_epoch - now_epoch) / 86400))
				days_str="$days"
				if [[ "$days" -lt 0 ]]; then
					color="$RED"
				elif [[ "$days" -le 14 ]]; then
					color="$YELLOW"
				else
					color="$GREEN"
				fi
			fi
			# Display YYYY-MM-DDTHH:MM:SSZ (drop fractional seconds)
			not_after=$(echo "$not_after" | sed -E 's/\.[0-9]+Z$/Z/')
		else
			not_after="—"
		fi

		printf "  %-20s %-30s %-8s " "$ns" "$name" "$ready"
		if [[ -n "$color" ]]; then
			printf "%b%-22s %-6s%b\n" "$color" "$not_after" "$days_str" "$NC"
		else
			printf "%-22s %-6s\n" "$not_after" "$days_str"
		fi
	done
}

echo
echo -e "  ${BOLD}Issuers:${NC}"
"$KUBE_CLI" get clusterissuer -o wide 2>/dev/null || echo -e "  ${DIM}No ClusterIssuers found${NC}"
echo
echo -e "  ${BOLD}Certificates:${NC}"
show_certificates_status
echo
