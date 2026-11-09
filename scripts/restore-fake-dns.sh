#!/bin/bash

################################################################################
# Script: restore-fake-dns.sh
# Description: Restore the cluster DNS configuration saved by install-fake-dns.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

BACKUP_NAMESPACE="${CERT_NAMESPACE:-default}"
BACKUP_CONFIGMAP="fake-dns-backup"

if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
	DNS_NAMESPACE="openshift-dns"
	DNS_CONFIGMAP="dns-default"
	DNS_ROLLOUT_TARGET="daemonset/dns-default"
else
	DNS_NAMESPACE="kube-system"
	DNS_CONFIGMAP="coredns"
	DNS_ROLLOUT_TARGET="deployment/coredns"
fi

backup_value() {
	"$KUBE_CLI" get configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" \
		-o jsonpath="$1" 2>/dev/null || true
}

restore_openshift_servers() {
	local servers="$1"

	if [[ -z "$servers" || "$servers" == "null" ]]; then
		"$KUBE_CLI" patch dns.operator.openshift.io/default --type=json \
			-p='[{"op":"remove","path":"/spec/servers"}]' 2>/dev/null || true
		return 0
	fi

	"$KUBE_CLI" patch dns.operator.openshift.io/default --type=merge \
		-p "{\"spec\":{\"servers\":${servers}}}"
}

# Removes only the fake-dns-example entry, for installs created before the
# backup ConfigMap existed. Never removes unrelated DNS servers.
remove_legacy_fake_entry() {
	local servers cleaned
	servers=$("$KUBE_CLI" get dns.operator.openshift.io/default -o json 2>/dev/null | jq -c '.spec.servers // null' || true)
	if [[ -z "$servers" || "$servers" == "null" ]]; then
		return 0
	fi

	if ! echo "$servers" | jq -e 'any(.[]; .name == "fake-dns-example")' >/dev/null 2>&1; then
		return 0
	fi

	cleaned=$(echo "$servers" | jq -c '[.[] | select(.name != "fake-dns-example")]')
	if [[ "$cleaned" == "[]" ]]; then
		"$KUBE_CLI" patch dns.operator.openshift.io/default --type=json \
			-p='[{"op":"remove","path":"/spec/servers"}]' 2>/dev/null || true
	else
		"$KUBE_CLI" patch dns.operator.openshift.io/default --type=merge \
			-p "{\"spec\":{\"servers\":${cleaned}}}"
	fi
	log_info "Removed the fake-dns-example entry (legacy install, no backup found)."
}

restore_kubernetes_corefile() {
	local corefile="$1"

	if [[ -z "$corefile" ]]; then
		log_warn "Backup ConfigMap has no Corefile; leaving CoreDNS unchanged."
		return 0
	fi

	"$KUBE_CLI" patch configmap "$DNS_CONFIGMAP" -n "$DNS_NAMESPACE" --type=merge \
		-p "$(jq -n --arg cf "$corefile" '{data:{Corefile:$cf}}')"
	"$KUBE_CLI" rollout status "$DNS_ROLLOUT_TARGET" -n "$DNS_NAMESPACE" --timeout=60s 2>/dev/null ||
		log_warn "CoreDNS rollout may still be in progress"
}

main() {
	require_cmd "$KUBE_CLI" jq

	if ! "$KUBE_CLI" get configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" &>/dev/null; then
		log_warn "No DNS backup found ($BACKUP_NAMESPACE/$BACKUP_CONFIGMAP)."
		if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
			remove_legacy_fake_entry
		else
			log_warn "Leaving CoreDNS configuration unchanged."
		fi
		return 0
	fi

	local mode
	mode=$(backup_value '{.data.mode}')
	case "$mode" in
	openshift)
		restore_openshift_servers "$(backup_value '{.data.servers\.json}')"
		;;
	kubernetes)
		restore_kubernetes_corefile "$(backup_value '{.data.Corefile}')"
		;;
	*)
		log_warn "Unknown DNS backup mode '${mode:-<empty>}'; leaving DNS unchanged."
		return 0
		;;
	esac

	"$KUBE_CLI" delete configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" --ignore-not-found=true
	log_success "DNS configuration restored."
}

main
