#!/bin/bash

################################################################################
# Script: create-selfsigned-issuer.sh
# Description: Create a self-signed CA chain for disconnected/air-gapped environments
#
# Creates:
#   1. SelfSigned ClusterIssuer (bootstrap)
#   2. Root CA Certificate (long-lived, RSA 4096)
#   3. CA ClusterIssuer (signs leaf certificates)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

YAML_DIR="${SCRIPT_DIR}/../yaml/issuers"

export SELFSIGNED_ISSUER_NAME="${SELFSIGNED_ISSUER_NAME:-selfsigned-issuer}"
export CA_ISSUER_NAME="${CA_ISSUER_NAME:-selfsigned-ca-issuer}"
export ROOT_CA_NAME="${ROOT_CA_NAME:-root-ca}"
export ROOT_CA_NAMESPACE="${ROOT_CA_NAMESPACE:-cert-manager}"
export ROOT_CA_COMMON_NAME="${ROOT_CA_COMMON_NAME:-cluster-root-ca}"
export ROOT_CA_ORG="${ROOT_CA_ORG:-OpenShift}"
export ROOT_CA_SECRET_NAME="${ROOT_CA_SECRET_NAME:-root-ca-secret}"
export ROOT_CA_DURATION="${ROOT_CA_DURATION:-87600h}"
export ROOT_CA_RENEW_BEFORE="${ROOT_CA_RENEW_BEFORE:-8760h}"

check_existing_issuer() {
	log_info "Checking for existing CA resources..."

	local exists=false

	if $KUBE_CLI get clusterissuer "$SELFSIGNED_ISSUER_NAME" &>/dev/null; then
		log_warn "ClusterIssuer '$SELFSIGNED_ISSUER_NAME' already exists."
		exists=true
	fi

	if $KUBE_CLI get clusterissuer "$CA_ISSUER_NAME" &>/dev/null; then
		log_warn "ClusterIssuer '$CA_ISSUER_NAME' already exists."
		exists=true
	fi

	if $KUBE_CLI get certificate "$ROOT_CA_NAME" -n "$ROOT_CA_NAMESPACE" &>/dev/null; then
		log_warn "Root CA Certificate '$ROOT_CA_NAME' already exists in namespace '$ROOT_CA_NAMESPACE'."
		exists=true
	fi

	if [ "$exists" = true ]; then
		echo
		if ! confirm "Overwrite existing resources?"; then
			log_info "Keeping existing resources."
			exit 0
		fi
	fi
}

display_configuration() {
	print_header "Self-Signed CA Configuration"
	print_summary \
		"CA Issuer Name" "$CA_ISSUER_NAME" \
		"Root CA Name" "$ROOT_CA_NAME" \
		"Root CA Namespace" "$ROOT_CA_NAMESPACE" \
		"Root CA Common Name" "$ROOT_CA_COMMON_NAME" \
		"Root CA Organization" "$ROOT_CA_ORG" \
		"Root CA Secret" "$ROOT_CA_SECRET_NAME" \
		"Root CA Duration" "$ROOT_CA_DURATION" \
		"Root CA Renew Before" "$ROOT_CA_RENEW_BEFORE"
}

create_selfsigned_issuer() {
	log_info "Step 1/3: Creating SelfSigned ClusterIssuer (bootstrap)..."
	apply_yaml_template "$YAML_DIR/selfsigned-clusterissuer.yaml" "SelfSigned ClusterIssuer"

	log_info "Waiting for SelfSigned ClusterIssuer to be ready..."
	retry 10 2 "$KUBE_CLI" wait --for=condition=Ready clusterissuer/"$SELFSIGNED_ISSUER_NAME" --timeout=30s
	log_success "SelfSigned ClusterIssuer is ready."
}

create_root_ca() {
	log_info "Step 2/3: Creating Root CA Certificate..."
	apply_yaml_template "$YAML_DIR/root-ca-certificate.yaml" "Root CA Certificate"

	log_info "Waiting for Root CA Certificate to be issued..."
	retry 15 2 "$KUBE_CLI" wait --for=condition=Ready certificate/"$ROOT_CA_NAME" -n "$ROOT_CA_NAMESPACE" --timeout=30s
	log_success "Root CA Certificate is ready."
}

create_ca_issuer() {
	log_info "Step 3/3: Creating CA ClusterIssuer..."
	apply_yaml_template "$YAML_DIR/ca-clusterissuer.yaml" "CA ClusterIssuer"

	log_info "Waiting for CA ClusterIssuer to be ready..."
	retry 10 2 "$KUBE_CLI" wait --for=condition=Ready clusterissuer/"$CA_ISSUER_NAME" --timeout=30s
	log_success "CA ClusterIssuer is ready."
}

display_next_steps() {
	echo
	log_success "Self-signed CA chain created successfully!"
	echo
	echo "CA Issuer '$CA_ISSUER_NAME' is ready to sign certificates."
	echo
	echo "Next steps:"
	echo
	echo "1. View CA chain status:"
	echo "   oc get clusterissuer"
	echo "   oc get certificate -n $ROOT_CA_NAMESPACE"
	echo
	echo "2. Create a test certificate:"
	echo "   cat <<EOF | oc apply -f -"
	echo "   apiVersion: cert-manager.io/v1"
	echo "   kind: Certificate"
	echo "   metadata:"
	echo "     name: my-test-cert"
	echo "     namespace: default"
	echo "   spec:"
	echo "     secretName: my-test-cert-tls"
	echo "     issuerRef:"
	echo "       name: $CA_ISSUER_NAME"
	echo "       kind: ClusterIssuer"
	echo "     dnsNames:"
	echo "     - test.example.com"
	echo "   EOF"
	echo
	echo "3. Extract root CA for kubeconfig trust:"
	echo "   oc get secret $ROOT_CA_SECRET_NAME -n $ROOT_CA_NAMESPACE -o jsonpath='{.data.ca\\.crt}' | base64 -d"
	echo
}

main() {
	print_header "Create Self-Signed CA Chain"

	require_cmd "$KUBE_CLI" envsubst
	require_cluster
	require_cert_manager

	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	display_configuration
	check_existing_issuer
	create_selfsigned_issuer
	create_root_ca
	create_ca_issuer
	display_next_steps
}

main
