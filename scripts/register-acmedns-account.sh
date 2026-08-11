#!/bin/bash

################################################################################
# Script: register-acmedns-account.sh
# Description: Register an acme-dns account and create cert-manager credentials
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

ACMEDNS_NAMESPACE="${ACMEDNS_NAMESPACE:-acme-dns}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
ACMEDNS_SECRET_NAME="${ACMEDNS_SECRET_NAME:-acme-dns-credentials}"
ACMEDNS_DOMAIN="${ACMEDNS_DOMAIN:-example.com}"

register_account() {
	log_info "Registering new acme-dns account..."

	local acmedns_pod
	acmedns_pod=$("$KUBE_CLI" get pods -n "$ACMEDNS_NAMESPACE" -l app=acme-dns \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

	if [ -z "$acmedns_pod" ]; then
		log_error "Could not find acme-dns pod"
		exit 1
	fi

	local response
	response=$("$KUBE_CLI" exec "$acmedns_pod" -n "$ACMEDNS_NAMESPACE" -- \
		sh -c 'if command -v wget >/dev/null 2>&1; then wget -qO- --post-data="" http://localhost:8080/register; else curl -sf -X POST http://localhost:8080/register; fi' || echo "")

	if [ -z "$response" ]; then
		log_error "Failed to register acme-dns account"
		log_info "Check that acme-dns is running: $KUBE_CLI get pods -n $ACMEDNS_NAMESPACE"
		exit 1
	fi

	if ! echo "$response" | jq -e '.username' &>/dev/null; then
		log_error "Unexpected registration response: $response"
		exit 1
	fi

	read -r ACMEDNS_USERNAME ACMEDNS_PASSWORD ACMEDNS_FULLDOMAIN ACMEDNS_SUBDOMAIN \
		< <(echo "$response" | jq -r '[.username, .password, .fulldomain, .subdomain] | @tsv')

	log_success "Account registered successfully"
}

create_credentials_secret() {
	log_info "Creating credentials secret in $CERT_MANAGER_NAMESPACE..."

	local credentials_json
	credentials_json=$(jq -n \
		--arg domain "$ACMEDNS_DOMAIN" \
		--arg username "$ACMEDNS_USERNAME" \
		--arg password "$ACMEDNS_PASSWORD" \
		--arg fulldomain "$ACMEDNS_FULLDOMAIN" \
		--arg subdomain "$ACMEDNS_SUBDOMAIN" \
		'{($domain): {"username": $username, "password": $password, "fulldomain": $fulldomain, "subdomain": $subdomain}}')

	"$KUBE_CLI" create secret generic "$ACMEDNS_SECRET_NAME" \
		-n "$CERT_MANAGER_NAMESPACE" \
		--from-literal=acmedns.json="$credentials_json" \
		--dry-run=client -o yaml | "$KUBE_CLI" apply -f -

	log_success "Secret '$ACMEDNS_SECRET_NAME' created in namespace '$CERT_MANAGER_NAMESPACE'"
}

display_results() {
	print_header "acme-dns Registration Complete"

	print_summary \
		"Username" "$ACMEDNS_USERNAME" \
		"Subdomain" "$ACMEDNS_SUBDOMAIN" \
		"Full Domain" "$ACMEDNS_FULLDOMAIN" \
		"Secret" "$CERT_MANAGER_NAMESPACE/$ACMEDNS_SECRET_NAME" \
		"Domain" "$ACMEDNS_DOMAIN"

	echo
	echo "Next steps:"
	echo
	echo "1. Create a CNAME record pointing to acme-dns:"
	echo "   _acme-challenge.${ACMEDNS_DOMAIN}. CNAME ${ACMEDNS_FULLDOMAIN}."
	echo
	echo "2. Create a DNS-01 ClusterIssuer referencing the secret:"
	echo "   apiVersion: cert-manager.io/v1"
	echo "   kind: ClusterIssuer"
	echo "   metadata:"
	echo "     name: acmedns-issuer"
	echo "   spec:"
	echo "     acme:"
	echo "       solvers:"
	echo "       - dns01:"
	echo "           acmeDNS:"
	echo "             host: http://acme-dns.${ACMEDNS_NAMESPACE}.svc.cluster.local:8080"
	echo "             accountSecretRef:"
	echo "               name: ${ACMEDNS_SECRET_NAME}"
	echo "               key: acmedns.json"
	echo
}

main() {
	print_header "Register acme-dns Account"

	require_cmd jq
	require_cluster

	if ! check_deployment_exists acme-dns "$ACMEDNS_NAMESPACE"; then
		log_error "acme-dns is not installed."
		log_hint "Run 'make install-local-dns' first"
		exit 1
	fi

	ensure_namespace "$CERT_MANAGER_NAMESPACE"

	register_account
	create_credentials_secret
	display_results
}

main
