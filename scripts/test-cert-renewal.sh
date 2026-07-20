#!/bin/bash

################################################################################
# Script: test-cert-renewal.sh
# Description: Test certificate automatic renewal by creating a short-lived cert
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/certificates"

export CERT_NAME="${CERT_NAME:-renewal-test}"
export CERT_NAMESPACE="${CERT_NAMESPACE:-default}"
export CERT_SECRET_NAME="${CERT_SECRET_NAME:-renewal-test-tls}"
export ISSUER_NAME="${ISSUER_NAME:-selfsigned-ca-issuer}"
export CERT_DNS_NAME="${CERT_DNS_NAME:-renewal-test.example.com}"
export CERT_DURATION="${CERT_DURATION:-6m}"
export CERT_RENEW_BEFORE="${CERT_RENEW_BEFORE:-3m}"

POLL_INTERVAL=15
MAX_WAIT=600

get_cert_serial() {
	"$KUBE_CLI" get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" \
		-o jsonpath='{.data.tls\.crt}' 2>/dev/null |
		base64 -d 2>/dev/null |
		openssl x509 -noout -serial 2>/dev/null |
		cut -d= -f2 || echo ""
}

create_short_lived_cert() {
	log_info "Creating short-lived certificate..."
	log_info "  Duration: $CERT_DURATION, Renew Before: $CERT_RENEW_BEFORE"
	log_info "  Issuer: $ISSUER_NAME"

	apply_yaml_template "$YAML_DIR/short-lived-certificate.yaml" "Certificate"
}

wait_for_initial_issuance() {
	log_info "Waiting for initial certificate issuance..."

	retry 24 5 "$KUBE_CLI" wait --for=condition=Ready \
		"certificate/$CERT_NAME" -n "$CERT_NAMESPACE" --timeout=5s

	log_success "Certificate issued successfully"
}

wait_for_renewal() {
	local initial_serial="$1"
	log_info "Waiting for automatic renewal (polling every ${POLL_INTERVAL}s, max ${MAX_WAIT}s)..."
	log_info "Initial serial: $initial_serial"

	local elapsed=0
	while [ "$elapsed" -lt "$MAX_WAIT" ]; do
		local current_serial
		current_serial=$(get_cert_serial)

		if [ -n "$current_serial" ] && [ "$current_serial" != "$initial_serial" ]; then
			log_success "Certificate renewed!"
			log_info "New serial: $current_serial"
			return 0
		fi

		local remaining=$((MAX_WAIT - elapsed))
		if [ $((elapsed % 60)) -eq 0 ]; then
			log_info "Still waiting... (${elapsed}s elapsed, ${remaining}s remaining)"
		fi
		sleep "$POLL_INTERVAL"
		elapsed=$((elapsed + POLL_INTERVAL))
	done

	log_error "Timed out waiting for renewal after ${MAX_WAIT}s"
	return 1
}

verify_renewed_cert() {
	local initial_serial="$1"

	local cert_data
	cert_data=$("$KUBE_CLI" get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" \
		-o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)

	local renewed_serial not_before not_after
	renewed_serial=$(echo "$cert_data" | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2 || echo "unknown")
	not_before=$(echo "$cert_data" | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2 || echo "unknown")
	not_after=$(echo "$cert_data" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")

	print_summary \
		"Initial Serial" "$initial_serial" \
		"Renewed Serial" "$renewed_serial" \
		"Not Before" "$not_before" \
		"Not After" "$not_after" \
		"Result" "RENEWED"
}

main() {
	print_header "Certificate Renewal Test"

	require_cmd openssl envsubst
	require_cluster
	require_cert_manager

	create_short_lived_cert
	wait_for_initial_issuance

	local initial_serial
	initial_serial=$(get_cert_serial)

	if [ -z "$initial_serial" ]; then
		log_error "Could not read certificate serial from secret $CERT_SECRET_NAME"
		exit 1
	fi

	if wait_for_renewal "$initial_serial"; then
		verify_renewed_cert "$initial_serial"
		log_success "Certificate renewal test passed!"
	else
		log_error "Certificate renewal test failed"
		log_info "Check cert-manager logs: $KUBE_CLI logs -n cert-manager deployment/cert-manager --tail=50"
		exit 1
	fi
}

main
