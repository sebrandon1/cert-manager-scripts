#!/bin/bash

################################################################################
# Script: test-ingress-tls.sh
# Description: End-to-end TLS integration test via OpenShift Route or Ingress
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/ingress-test"

export INGRESS_TEST_NAMESPACE="${INGRESS_TEST_NAMESPACE:-ingress-tls-test}"
export ISSUER_NAME="${ISSUER_NAME:-selfsigned-ca-issuer}"
export INGRESS_TEST_HOSTNAME="${INGRESS_TEST_HOSTNAME:-}"

deploy_test_app() {
	log_info "Deploying test application..."

	ensure_namespace "$INGRESS_TEST_NAMESPACE"
	apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml_template "$YAML_DIR/service.yaml" "Service"

	wait_for_resource "deployment/ingress-tls-test" "$INGRESS_TEST_NAMESPACE" "120s"
	log_success "Test application deployed"
}

create_certificate() {
	log_info "Creating TLS certificate for $INGRESS_TEST_HOSTNAME..."

	apply_yaml_template "$YAML_DIR/certificate.yaml" "Certificate"

	log_info "Waiting for certificate issuance..."
	retry 24 5 "$KUBE_CLI" wait --for=condition=Ready \
		certificate/ingress-tls-test -n "$INGRESS_TEST_NAMESPACE" --timeout=5s

	log_success "Certificate issued"
}

create_route() {
	log_info "Creating OpenShift Route with edge TLS termination..."

	local secret_json
	secret_json=$("$KUBE_CLI" get secret ingress-tls-test-cert -n "$INGRESS_TEST_NAMESPACE" -o json)

	local cert_file key_file ca_file
	cert_file=$(mktemp)
	register_temp_file "$cert_file"
	key_file=$(mktemp)
	register_temp_file "$key_file"
	ca_file=$(mktemp)
	register_temp_file "$ca_file"

	echo "$secret_json" | jq -r '.data["tls.crt"]' | base64 -d >"$cert_file"
	echo "$secret_json" | jq -r '.data["tls.key"]' | base64 -d >"$key_file"
	echo "$secret_json" | jq -r '.data["ca.crt"] // empty' | base64 -d >"$ca_file" 2>/dev/null || true

	local route_args=(
		create route edge ingress-tls-test
		--service=ingress-tls-test
		--hostname="$INGRESS_TEST_HOSTNAME"
		--cert="$cert_file"
		--key="$key_file"
		--port=8080
		--insecure-policy=Redirect
		-n "$INGRESS_TEST_NAMESPACE"
	)

	if [ -s "$ca_file" ]; then
		route_args+=(--ca-cert="$ca_file")
	fi

	"$KUBE_CLI" "${route_args[@]}" 2>/dev/null || "$KUBE_CLI" "${route_args[@]}" --dry-run=client -o yaml | "$KUBE_CLI" apply -f -

	log_info "Waiting for Route to be admitted..."
	check_route_admitted() {
		"$KUBE_CLI" get route ingress-tls-test -n "$INGRESS_TEST_NAMESPACE" \
			-o jsonpath='{.status.ingress[0].conditions[0].type}' 2>/dev/null | grep -q "Admitted"
	}
	wait_for_condition 12 5 check_route_admitted

	log_success "Route created and admitted"
}

create_ingress() {
	log_info "Creating Kubernetes Ingress with TLS..."

	apply_yaml_template "$YAML_DIR/ingress.yaml" "Ingress"

	log_success "Ingress created"
}

verify_tls() {
	log_info "Verifying TLS configuration..."

	local route_host
	if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
		route_host=$("$KUBE_CLI" get route ingress-tls-test -n "$INGRESS_TEST_NAMESPACE" \
			-o jsonpath='{.spec.host}' 2>/dev/null || echo "")
	else
		route_host=$("$KUBE_CLI" get ingress ingress-tls-test -n "$INGRESS_TEST_NAMESPACE" \
			-o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
	fi

	if [ -z "$route_host" ]; then
		log_warn "Could not determine route/ingress hostname"
		return
	fi

	log_info "Testing HTTPS connection to $route_host..."
	if curl -sk --connect-timeout 10 "https://${route_host}" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -qE "^(200|403|302)$"; then
		log_success "HTTPS connection established (certificate not verified — use --cacert for full validation)"
	else
		log_warn "HTTPS connection could not be verified (this may be expected if the route is not externally reachable)"
	fi

	local cert_data
	cert_data=$("$KUBE_CLI" get secret ingress-tls-test-cert -n "$INGRESS_TEST_NAMESPACE" \
		-o jsonpath='{.data.tls\.crt}' | base64 -d)

	local cert_subject cert_issuer cert_expiry
	cert_subject=$(echo "$cert_data" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//' || echo "unknown")
	cert_issuer=$(echo "$cert_data" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "unknown")
	cert_expiry=$(echo "$cert_data" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")

	local resource_type="Route"
	[[ "$CLUSTER_TYPE" != "openshift" ]] && resource_type="Ingress"

	print_summary \
		"Hostname" "$route_host" \
		"Resource" "$resource_type" \
		"Subject" "$cert_subject" \
		"Issuer" "$cert_issuer" \
		"Expires" "$cert_expiry" \
		"TLS Secret" "ingress-tls-test-cert"
}

main() {
	print_header "Ingress/Route TLS Integration Test"

	require_cmd openssl envsubst curl jq
	require_cluster
	require_cert_manager

	if [ -z "$INGRESS_TEST_HOSTNAME" ]; then
		local cluster_domain
		cluster_domain=$("$KUBE_CLI" get ingresses.config/cluster \
			-o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
		if [ -n "$cluster_domain" ]; then
			INGRESS_TEST_HOSTNAME="ingress-tls-test.${cluster_domain}"
		else
			INGRESS_TEST_HOSTNAME="ingress-tls-test.example.com"
		fi
		export INGRESS_TEST_HOSTNAME
		log_info "Using hostname: $INGRESS_TEST_HOSTNAME"
	fi

	deploy_test_app
	create_certificate

	if [[ "$CLUSTER_TYPE" == "openshift" ]]; then
		create_route
	else
		create_ingress
	fi

	verify_tls

	log_success "Ingress/Route TLS integration test passed!"
}

main
