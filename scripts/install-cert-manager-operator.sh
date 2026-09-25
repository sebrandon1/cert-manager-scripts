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
check_help "$@" && exit 0
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
		local current_channel
		current_channel=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.spec.channel}')
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
	apply_yaml_template "$YAML_DIR/operatorgroup.yaml" "OperatorGroup" || return 1

	# Create Subscription
	apply_yaml_template "$YAML_DIR/subscription.yaml" "Subscription" || return 1

	log_info "Resources applied. Waiting for operator installation to complete..."
}

# Return the CSV currently selected by the Subscription, falling back to the
# pinned startingCSV while OLM is still creating the Subscription status.
get_operator_csv_name() {
	local csv_name
	csv_name=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" \
		-o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
	if [ -z "$csv_name" ]; then
		csv_name="cert-manager-operator.${CERT_MANAGER_VERSION}"
	fi
	printf '%s\n' "$csv_name"
}

get_operator_csv_phase() {
	local csv_name
	csv_name=$(get_operator_csv_name)
	oc get csv "$csv_name" -n "$OPERATOR_NAMESPACE" \
		-o jsonpath='{.status.phase}' 2>/dev/null || true
}

olm_has_terminal_failure() {
	local phase conditions install_plan install_plan_phase
	phase=$(get_operator_csv_phase)
	if [ "$phase" = "Failed" ]; then
		log_error "Operator CSV $(get_operator_csv_name) is in Failed phase."
		return 0
	fi

	conditions=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" \
		-o jsonpath='{range .status.conditions[*]}{.type}{"|"}{.status}{"|"}{.reason}{"\n"}{end}' 2>/dev/null || true)
	if printf '%s\n' "$conditions" | grep -Eq '^(ResolutionFailed|InstallPlanFailed)\|True\|'; then
		log_error "Subscription '$OPERATOR_NAME' reports a terminal OLM failure:"
		printf '%s\n' "$conditions" | grep -E '^(ResolutionFailed|InstallPlanFailed)\|True\|' || true
		return 0
	fi

	install_plan=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" \
		-o jsonpath='{.status.installPlanRef.name}' 2>/dev/null || true)
	if [ -n "$install_plan" ]; then
		install_plan_phase=$(oc get installplan "$install_plan" -n "$OPERATOR_NAMESPACE" \
			-o jsonpath='{.status.phase}' 2>/dev/null || true)
		if [ "$install_plan_phase" = "Failed" ]; then
			log_error "InstallPlan '$install_plan' is in Failed phase."
			return 0
		fi
	fi

	return 1
}

show_olm_diagnostics() {
	local csv_name install_plan
	csv_name=$(get_operator_csv_name)
	install_plan=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" \
		-o jsonpath='{.status.installPlanRef.name}' 2>/dev/null || true)

	log_warn "--- OLM diagnostics for namespace '$OPERATOR_NAMESPACE' ---"
	log_info "Subscription:"
	oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o yaml 2>/dev/null || true
	log_info "InstallPlans:"
	oc get installplan -n "$OPERATOR_NAMESPACE" -o wide 2>/dev/null || true
	if [ -n "$install_plan" ]; then
		oc describe installplan "$install_plan" -n "$OPERATOR_NAMESPACE" 2>/dev/null || true
	fi
	log_info "CSV:"
	oc get csv "$csv_name" -n "$OPERATOR_NAMESPACE" -o wide 2>/dev/null || true
	if oc get csv "$csv_name" -n "$OPERATOR_NAMESPACE" &>/dev/null; then
		oc describe csv "$csv_name" -n "$OPERATOR_NAMESPACE" 2>/dev/null || true
	fi
	log_info "CatalogSources:"
	oc get catalogsource -n openshift-marketplace -o wide 2>/dev/null || true
	log_info "Namespace events:"
	oc get events -n "$OPERATOR_NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -40 || true
	log_warn "--- End OLM diagnostics ---"
}

wait_for_operator_csv() {
	local max_attempts=60 attempt=1 phase
	log_info "Waiting up to five minutes for the operator CSV to reach Succeeded phase..."
	while [ "$attempt" -le "$max_attempts" ]; do
		phase=$(get_operator_csv_phase)
		if [ "$phase" = "Succeeded" ]; then
			log_success "Operator CSV $(get_operator_csv_name) is in Succeeded phase."
			return 0
		fi

		if [ "$phase" = "Failed" ] || olm_has_terminal_failure; then
			return 2
		fi

		if [ $((attempt % 6)) -eq 0 ]; then
			log_info "Still waiting for the operator CSV... ($attempt/$max_attempts)"
		fi
		if [ "$attempt" -lt "$max_attempts" ]; then
			sleep 5
		fi
		attempt=$((attempt + 1))
	done

	log_warn "Timed out waiting for the operator CSV to reach Succeeded phase."
	return 1
}

# Function to wait for operator to be ready. A single retry is allowed only
# when OLM is still progressing and has not reported a terminal failure.
wait_for_operator() {
	local attempt=1 wait_status
	while [ "$attempt" -le 2 ]; do
		if wait_for_operator_csv; then
			break
		else
			wait_status=$?
		fi

		show_olm_diagnostics
		if [ "$wait_status" -eq 2 ] || olm_has_terminal_failure; then
			log_error "OLM reported a terminal failure; the operator installation will not be retried."
			return 1
		fi

		if [ "$attempt" -eq 2 ]; then
			log_error "Operator CSV did not become Succeeded after two five-minute attempts."
			return 1
		fi

		log_warn "OLM is still progressing without a terminal failure; retrying the operator install once."
		install_operator || return 1
		attempt=$((attempt + 1))
	done

	log_info "Waiting for operator controller deployment to become ready..."
	wait_for_resource "deployment/cert-manager-operator-controller-manager" "$OPERATOR_NAMESPACE" 300s || return 1
	log_success "Operator is ready!"
}

# Function to verify installation
verify_installation() {
	log_info "Verifying installation..."

	# Check operator pod
	log_info "Checking operator pod status..."
	oc get pods -n "$OPERATOR_NAMESPACE" || return 1

	# Check CSV
	log_info "Checking ClusterServiceVersion..."
	oc get csv -n "$OPERATOR_NAMESPACE" || return 1

	# Check if cert-manager namespace exists (created by operator)
	if oc get namespace "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
		log_info "cert-manager namespace exists."

		# Check cert-manager deployments
		log_info "Checking cert-manager components..."
		oc get deployments -n "$CERT_MANAGER_NAMESPACE" || return 1
	else
		log_warn "cert-manager namespace not yet created. The operator will create it."
	fi

	log_info "Installation verification complete!"
}

# Function to display next steps
display_next_steps() {
	print_header "Installation completed successfully!"
	echo "Next steps:"
	echo "1. Verify the operator is running:"
	echo "   oc get pods -n $OPERATOR_NAMESPACE"
	echo
	echo "2. Check cert-manager components (may take a moment to appear):"
	echo "   oc get pods -n $CERT_MANAGER_NAMESPACE"
	echo
	echo "3. Quick test HTTP-01 challenges:"
	echo "   make quick-http-test"
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

	check_prerequisites || return 1
	check_existing_installation || return 1
	ensure_namespace "$OPERATOR_NAMESPACE" || return 1
	install_operator || return 1
	wait_for_operator || return 1
	verify_installation || return 1
	display_next_steps
}

# Run main function
if ! main; then
	log_hint "Operator install failed. Check CSV status or run: make uninstall-cert-manager-operator"
	exit 1
fi
