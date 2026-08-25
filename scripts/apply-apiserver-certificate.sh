#!/bin/bash

################################################################################
# Script: apply-apiserver-certificate.sh
# Description: Apply a cert-manager-issued certificate to the OpenShift API server
#
# Patches APIServer/cluster to reference the cert-manager-issued secret so that
# the OpenShift API server serves the custom TLS certificate.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

CERT_NAMESPACE="${CERT_NAMESPACE:-openshift-config}"
CERT_NAME="apiserver-cert"
SECRET_NAME="apiserver-cert-tls"

check_prerequisites() {
	log_info "Checking prerequisites..."

	require_cmd "$KUBE_CLI" jq
	require_cluster
	require_cluster_admin

	if [[ "${CLUSTER_TYPE:-}" != "openshift" ]]; then
		log_error "This script requires an OpenShift cluster (CLUSTER_TYPE=openshift)."
		log_hint "Use 'oc' and connect to an OpenShift cluster before running."
		exit 1
	fi

	local ready
	ready=$("$KUBE_CLI" get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" \
		-o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
	if [[ "$ready" != "True" ]]; then
		log_error "Certificate '$CERT_NAME' in '$CERT_NAMESPACE' is not Ready."
		log_hint "Run 'make create-apiserver-cert' and wait for the certificate to be issued."
		exit 1
	fi

	local has_crt has_key
	has_crt=$("$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" \
		-o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
	has_key=$("$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" \
		-o jsonpath='{.data.tls\.key}' 2>/dev/null || true)
	if [[ -z "$has_crt" || -z "$has_key" ]]; then
		log_error "Secret '$SECRET_NAME' in '$CERT_NAMESPACE' is missing tls.crt or tls.key."
		exit 1
	fi

	log_success "Prerequisites check passed."
}

backup_apiserver() {
	local backup_file
	backup_file="/tmp/apiserver-cluster-backup-$(date +%Y%m%d-%H%M%S).yaml"
	log_info "Backing up APIServer/cluster to $backup_file ..."
	"$KUBE_CLI" get apiserver cluster -o yaml >"$backup_file"
	log_success "Backup saved: $backup_file"
	echo "$backup_file"
}

is_already_applied() {
	local existing
	existing=$("$KUBE_CLI" get apiserver cluster \
		-o jsonpath='{.spec.servingCerts.namedCertificates[*].servingCertificate.name}' 2>/dev/null || true)
	echo "$existing" | grep -qw "$SECRET_NAME"
}

wait_for_rollout() {
	local backup_file="$1"
	local max_attempts=300 # 300 × 2s = 600s timeout

	log_info "Waiting for kube-apiserver clusteroperator to become Available ..."

	check_co_stable() {
		local available progressing degraded
		available=$("$KUBE_CLI" get clusteroperator kube-apiserver \
			-o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
		progressing=$("$KUBE_CLI" get clusteroperator kube-apiserver \
			-o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null || true)
		degraded=$("$KUBE_CLI" get clusteroperator kube-apiserver \
			-o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null || true)
		[[ "$available" == "True" && "$progressing" == "False" && "$degraded" == "False" ]]
	}

	if wait_for_condition "$max_attempts" 2 check_co_stable; then
		log_success "kube-apiserver clusteroperator is stable."
	else
		log_error "Timed out waiting for kube-apiserver to stabilize."
		log_hint "Restore the backup: $KUBE_CLI apply -f $backup_file"
		exit 1
	fi
}

main() {
	print_header "Apply API Server Certificate"
	check_prerequisites

	local backup_file
	backup_file=$(backup_apiserver)

	echo
	log_warn "Applying this certificate will roll the kube-apiserver."
	log_warn "API connectivity may be briefly disrupted."
	log_warn "Backup saved at: $backup_file"
	log_hint "To restore: $KUBE_CLI apply -f $backup_file"
	echo

	if is_already_applied; then
		log_success "APIServer/cluster already references '$SECRET_NAME'. Nothing to do."
		"$SCRIPT_DIR/troubleshooting/verify-apiserver-certificate.sh"
		exit 0
	fi

	local api_host
	api_host=$("$KUBE_CLI" whoami --show-server |
		sed -E 's|https?://([^:/]+).*|\1|')
	log_info "API server hostname: $api_host"

	confirm "Patch APIServer/cluster to use '$SECRET_NAME'?" || {
		log_info "Cancelled. No changes made."
		exit 0
	}

	local patch
	patch=$(
		cat <<EOF
{"spec":{"servingCerts":{"namedCertificates":[{"names":["$api_host"],"servingCertificate":{"name":"$SECRET_NAME"}}]}}}
EOF
	)
	"$KUBE_CLI" patch apiserver cluster --type=merge -p "$patch"
	log_success "APIServer/cluster patched."

	wait_for_rollout "$backup_file"

	"$SCRIPT_DIR/troubleshooting/verify-apiserver-certificate.sh"
}

main
