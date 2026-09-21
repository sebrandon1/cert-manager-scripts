#!/bin/bash

################################################################################
# Script: recover-install.sh
# Description: Detect and roll back half-installed test components (not the operator)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"
FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"
ACMEDNS_NAMESPACE="${ACMEDNS_NAMESPACE:-acme-dns}"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"

half_installed=()

namespace_exists() {
	"$KUBE_CLI" get namespace "$1" &>/dev/null
}

mark_half() {
	half_installed+=("$1")
}

detect_half_installed() {
	# Pebble: namespace exists but deployment not healthy
	if namespace_exists "$PEBBLE_NAMESPACE" && ! check_deployment_exists pebble "$PEBBLE_NAMESPACE"; then
		mark_half "pebble"
	fi

	# fake-dns
	if namespace_exists "$FAKEDNS_NAMESPACE" && ! check_deployment_exists fake-dns-api "$FAKEDNS_NAMESPACE"; then
		mark_half "fake-dns"
	fi

	# acme-dns
	if namespace_exists "$ACMEDNS_NAMESPACE" && ! check_deployment_exists acme-dns "$ACMEDNS_NAMESPACE"; then
		mark_half "acme-dns"
	fi

	# challtestsrv: deployment exists but not ready
	if "$KUBE_CLI" get deployment pebble-challtestsrv -n "$PEBBLE_NAMESPACE" &>/dev/null &&
		! check_deployment_exists pebble-challtestsrv "$PEBBLE_NAMESPACE"; then
		mark_half "challtestsrv"
	fi

	# monitoring: ServiceMonitor or PrometheusRule present without healthy cert-manager is unusual;
	# treat partial monitoring as SM/PR present but missing the other
	local has_sm=false has_rule=false
	"$KUBE_CLI" get servicemonitor cert-manager -n "$CERT_MANAGER_NAMESPACE" &>/dev/null && has_sm=true
	"$KUBE_CLI" get prometheusrule cert-manager-alerts -n "$CERT_MANAGER_NAMESPACE" &>/dev/null && has_rule=true
	if { [ "$has_sm" = true ] && [ "$has_rule" = false ]; } ||
		{ [ "$has_sm" = false ] && [ "$has_rule" = true ]; }; then
		mark_half "monitoring"
	fi

	# MinIO
	if namespace_exists "$MINIO_NAMESPACE" && ! check_deployment_exists minio "$MINIO_NAMESPACE"; then
		mark_half "minio"
	fi
}

clean_component() {
	local name="$1"
	case "$name" in
	pebble)
		make -C "$REPO_ROOT" clean-pebble
		;;
	fake-dns)
		make -C "$REPO_ROOT" clean-fake-dns
		make -C "$REPO_ROOT" clean-dns-config
		;;
	acme-dns)
		make -C "$REPO_ROOT" clean-acmedns
		;;
	challtestsrv)
		make -C "$REPO_ROOT" clean-challtestsrv
		;;
	monitoring)
		make -C "$REPO_ROOT" clean-monitoring
		;;
	minio)
		make -C "$REPO_ROOT" clean-ibu
		;;
	*)
		log_warn "Unknown component: $name"
		;;
	esac
}

main() {
	print_header "Recover Half-Installed Components"
	require_cmd "$KUBE_CLI"
	require_cluster

	detect_half_installed

	if [ ${#half_installed[@]} -eq 0 ]; then
		log_success "No half-installed components detected."
		exit 0
	fi

	log_warn "Half-installed components detected: ${half_installed[*]}"
	echo
	log_info "This will run the matching make clean-* targets."
	log_info "The cert-manager operator will NOT be uninstalled."
	echo

	if ! confirm "Roll back these components?"; then
		log_info "Cancelled."
		exit 0
	fi

	local name
	for name in "${half_installed[@]}"; do
		log_info "Cleaning $name..."
		if [[ "${DRY_RUN:-false}" == "true" ]]; then
			log_warn "DRY_RUN: would clean $name"
			continue
		fi
		clean_component "$name"
	done

	# Re-detect
	half_installed=()
	detect_half_installed
	if [ ${#half_installed[@]} -gt 0 ]; then
		log_error "Still half-installed after cleanup: ${half_installed[*]}"
		exit 1
	fi

	log_success "Recovery complete."
}

main
