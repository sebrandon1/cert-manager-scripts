#!/bin/bash

################################################################################
# Script: install-cert-manager-helm.sh
# Description: Install cert-manager via Helm for vanilla Kubernetes clusters
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0

export CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
export CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.0}"

main() {
	print_header "Install cert-manager via Helm"

	require_cmd "$KUBE_CLI" helm envsubst
	require_cluster

	if check_deployment_exists cert-manager "$CERT_MANAGER_NAMESPACE"; then
		log_info "cert-manager is already installed."
		return 0
	fi

	log_info "Adding Jetstack Helm repository..."
	helm repo add jetstack https://charts.jetstack.io --force-update
	helm repo update jetstack

	log_info "Installing cert-manager ${CERT_MANAGER_VERSION}..."
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace "$CERT_MANAGER_NAMESPACE" \
		--create-namespace \
		--version "${CERT_MANAGER_VERSION#v}" \
		--set crds.enabled=true \
		--wait --timeout 300s

	log_info "Verifying cert-manager installation..."
	"$KUBE_CLI" get pods -n "$CERT_MANAGER_NAMESPACE"
	wait_for_resource "deployment/cert-manager-webhook" "$CERT_MANAGER_NAMESPACE" "${DEPLOYMENT_READY_TIMEOUT:-120s}"

	log_success "cert-manager ${CERT_MANAGER_VERSION} installed via Helm."
}

main
