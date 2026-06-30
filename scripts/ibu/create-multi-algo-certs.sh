#!/bin/bash

################################################################################
# Script: create-multi-algo-certs.sh
# Description: Create test certificates with different key algorithms to validate
#              IBU behavior across ECDSA, RSA, and Ed25519 key types.
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
ISSUER_NAME="${ISSUER_NAME:-selfsigned-issuer}"
CERT_LABEL="ibu-multi-algo-test"

# Algorithm definitions: name:algorithm:size:expected_pem_type
ALGO_SPECS=(
	"ecdsa-p256:ECDSA:256:EC PRIVATE KEY"
	"ecdsa-p384:ECDSA:384:EC PRIVATE KEY"
	"rsa-2048:RSA:2048:RSA PRIVATE KEY"
	"rsa-4096:RSA:4096:RSA PRIVATE KEY"
	"ed25519:Ed25519::PRIVATE KEY"
)

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc jq
	require_cluster
	require_cert_manager
	log_success "Prerequisites met."
}

ensure_selfsigned_issuer() {
	if oc get clusterissuer "$ISSUER_NAME" &>/dev/null; then
		log_info "ClusterIssuer '$ISSUER_NAME' already exists."
		return 0
	fi

	log_info "Creating selfsigned ClusterIssuer..."
	cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ISSUER_NAME
spec:
  selfSigned: {}
EOF
}

create_algo_certificate() {
	local name_suffix="$1"
	local algorithm="$2"
	local size="$3"

	local cert_name="ibu-cert-${name_suffix}"
	local secret_name="${cert_name}-tls"

	if oc get certificate "$cert_name" -n "$TARGET_NAMESPACE" &>/dev/null; then
		log_warn "Certificate '$cert_name' already exists, skipping."
		return 0
	fi

	log_info "Creating certificate: $cert_name (algorithm=$algorithm${size:+, size=$size})..."

	local private_key_block=""
	if [[ -n "$size" ]]; then
		private_key_block="  privateKey:
    algorithm: $algorithm
    size: $size"
	else
		private_key_block="  privateKey:
    algorithm: $algorithm"
	fi

	cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $cert_name
  namespace: $TARGET_NAMESPACE
  labels:
    app: $CERT_LABEL
spec:
  secretName: $secret_name
  issuerRef:
    name: $ISSUER_NAME
    kind: ClusterIssuer
  dnsNames:
    - "${name_suffix}.ibu-test.example.com"
  duration: 8760h
$private_key_block
EOF
}

create_all_certificates() {
	log_info "Creating multi-algorithm test certificates in namespace '$TARGET_NAMESPACE'..."
	echo

	for spec in "${ALGO_SPECS[@]}"; do
		IFS=':' read -r name_suffix algorithm size _ <<<"$spec"
		create_algo_certificate "$name_suffix" "$algorithm" "$size"
	done

	echo
	log_info "All certificate resources created."
}

wait_for_certificates() {
	log_info "Waiting for certificates to become ready..."

	local max_attempts=60
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		local not_ready
		not_ready=$(oc get certificates -n "$TARGET_NAMESPACE" -l app="$CERT_LABEL" -o json 2>/dev/null |
			jq '[.items[] | select((.status.conditions // [] | map(select(.type=="Ready" and .status=="True")) | length) == 0)] | length')

		if [ "$not_ready" -eq 0 ]; then
			log_success "All certificates are ready!"
			return 0
		fi

		attempt=$((attempt + 1))
		if [ $((attempt % 5)) -eq 0 ]; then
			log_info "Still waiting... ($not_ready not ready, ${attempt}/${max_attempts})"
		fi
		sleep 2
	done

	log_error "Timeout waiting for certificates to become ready."
	log_info "Check status: oc get certificates -n $TARGET_NAMESPACE -l app=$CERT_LABEL"
	exit 1
}

verify_key_formats() {
	print_header "Key Format Verification"

	local pass_count=0
	local fail_count=0

	local secrets_json
	secrets_json=$(oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')

	printf "  %-22s %-18s %-18s %s\n" "CERTIFICATE" "EXPECTED" "ACTUAL" "STATUS"
	printf "  %-22s %-18s %-18s %s\n" "───────────" "────────" "──────" "──────"

	for spec in "${ALGO_SPECS[@]}"; do
		IFS=':' read -r name_suffix _ _ expected <<<"$spec"
		local cert_name="ibu-cert-${name_suffix}"
		local secret_name="${cert_name}-tls"

		local key_b64
		key_b64=$(echo "$secrets_json" | jq -r --arg name "$secret_name" \
			'.items[] | select(.metadata.name == $name) | .data["tls.key"] // ""')

		local actual
		actual=$(get_key_pem_type "$key_b64")

		local status
		if [ "$actual" = "$expected" ]; then
			status="PASS"
			pass_count=$((pass_count + 1))
		else
			status="FAIL"
			fail_count=$((fail_count + 1))
		fi

		printf "  %-22s %-18s %-18s %s\n" "$cert_name" "$expected" "$actual" "$status"
	done

	echo
	if [ "$fail_count" -eq 0 ]; then
		log_success "All ${pass_count} key formats match expected PEM types."
	else
		log_error "${fail_count} key format(s) did not match expected PEM type."
		exit 1
	fi
}

print_algo_summary() {
	echo
	echo "  Certificates created for IBU multi-algorithm testing:"
	echo
	printf "  %-22s %-10s %-6s %s\n" "NAME" "ALGORITHM" "SIZE" "EXPECTED PEM TYPE"
	printf "  %-22s %-10s %-6s %s\n" "────" "─────────" "────" "─────────────────"

	for spec in "${ALGO_SPECS[@]}"; do
		IFS=':' read -r name_suffix algorithm size expected <<<"$spec"
		printf "  %-22s %-10s %-6s %s\n" \
			"ibu-cert-${name_suffix}" "$algorithm" "${size:-n/a}" "$expected"
	done
	echo
}

main() {
	print_header "Multi-Algorithm Certificate Creation"
	check_prerequisites
	ensure_selfsigned_issuer
	create_all_certificates
	wait_for_certificates
	verify_key_formats
	print_algo_summary

	log_success "Multi-algorithm certificates ready for IBU testing."
	echo
	echo "  Next steps:"
	echo "    make verify-key-formats    # Re-verify key formats"
	echo "    make test-ibu-multi-algo   # Run IBU test with all algorithms"
	echo "    make clean-multi-algo-certs # Clean up"
	echo
}

main "$@"
