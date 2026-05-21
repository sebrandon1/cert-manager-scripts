#!/bin/bash

################################################################################
# Script: install-cert-manager-operator.sh
# Description: Install cert-manager Operator for Red Hat OpenShift
# Reference: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/yaml/cert-manager-operator"

# Configuration (exported for envsubst, can be overridden via .env)
export OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-cert-manager-operator}"
export CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
export OPERATOR_NAME="${OPERATOR_NAME:-openshift-cert-manager-operator}"
export CHANNEL="${CHANNEL:-stable-v1}"
export CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.0}"

# Function to check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	require_cmd oc envsubst
	require_cluster_admin

	# Check if YAML directory exists
	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	log_info "Prerequisites check passed."
}

# Function to check if operator is already installed
check_existing_installation() {
	log_info "Checking for existing cert-manager-operator installation..."

	if oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
		log_info "cert-manager-operator subscription already exists."

		# Get current version/channel
		local current_channel=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.spec.channel}')
		log_info "Current channel: $current_channel"

		# Check if it's healthy
		if oc get csv -n "$OPERATOR_NAMESPACE" | grep -q "cert-manager.*Succeeded"; then
			log_info "Operator is already installed and healthy."
			log_info "Installation is idempotent - will verify and ensure components are ready."
			return 0
		else
			log_warn "Operator exists but may not be healthy. Will attempt to reconcile."
			return 0
		fi
	fi

	log_info "No existing installation found. Will proceed with fresh installation."
}

# Function to install the operator
install_operator() {
	log_info "Installing cert-manager Operator for Red Hat OpenShift..."

	# Create OperatorGroup
	apply_yaml_template "$YAML_DIR/operatorgroup.yaml" "OperatorGroup"

	# Create Subscription
	apply_yaml_template "$YAML_DIR/subscription.yaml" "Subscription"

	log_info "Resources applied. Waiting for operator installation to complete..."
}

# Function to wait for operator to be ready
wait_for_operator() {
	# Wait for CSV to reach Succeeded phase
	wait_for_csv "$OPERATOR_NAMESPACE" "cert-manager" 60

	# Wait for operator deployment to be ready
	log_info "Waiting for operator deployment to be ready..."
	if oc get deployment cert-manager-operator-controller-manager -n "$OPERATOR_NAMESPACE" &>/dev/null; then
		wait_for_resource "deployment/cert-manager-operator-controller-manager" "$OPERATOR_NAMESPACE" 300s
	else
		log_warn "Operator deployment not found yet, but CSV is ready."
	fi

	log_success "Operator is ready!"
}

# Function to verify installation
verify_installation() {
	log_info "Verifying installation..."

	# Check operator pod
	log_info "Checking operator pod status..."
	oc get pods -n "$OPERATOR_NAMESPACE"

	# Check CSV
	log_info "Checking ClusterServiceVersion..."
	oc get csv -n "$OPERATOR_NAMESPACE"

	# Check if cert-manager namespace exists (created by operator)
	if oc get namespace "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
		log_info "cert-manager namespace exists."

		# Check cert-manager deployments
		log_info "Checking cert-manager components..."
		oc get deployments -n "$CERT_MANAGER_NAMESPACE"
	else
		log_warn "cert-manager namespace not yet created. The operator will create it."
	fi

	log_info "Installation verification complete!"
}

# Function to display next steps
display_next_steps() {
	echo
	log_info "========================================"
	log_info "Installation completed successfully!"
	log_info "========================================"
	echo
	echo "Next steps:"
	echo "1. Verify the operator is running:"
	echo "   oc get pods -n $OPERATOR_NAMESPACE"
	echo
	echo "2. Check cert-manager components (may take a moment to appear):"
	echo "   oc get pods -n $CERT_MANAGER_NAMESPACE"
	echo
	echo "3. Quick test DNS-01 challenges (air-gapped):"
	echo "   make quick-test"
	echo
	echo "4. Clean up test resources:"
	echo "   make clean"
	echo
}

# Main execution
main() {
	log_info "Starting cert-manager Operator installation..."
	log_info "Version: $CERT_MANAGER_VERSION (channel: $CHANNEL)"
	echo

	check_prerequisites
	check_existing_installation
	ensure_namespace "$OPERATOR_NAMESPACE"
	install_operator
	wait_for_operator
	verify_installation
	display_next_steps
}

# Run main function
main
