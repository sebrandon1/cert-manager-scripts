#!/bin/bash

################################################################################
# Script: install-oadp.sh
# Description: Install OADP (OpenShift API for Data Protection) operator
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/ibu/oadp"
OADP_NAMESPACE="${OADP_NAMESPACE:-openshift-adp}"
export MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minio}"
export MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minio123}"

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc
	require_cluster

	# Check MinIO is running
	if ! oc get deployment minio -n minio &>/dev/null; then
		log_error "MinIO is not installed. Run 'make install-minio' first."
		exit 1
	fi

	log_info "Prerequisites check passed."
}

check_existing_installation() {
	log_info "Checking for existing OADP installation..."

	if oc get subscription redhat-oadp-operator -n "$OADP_NAMESPACE" &>/dev/null; then
		log_info "OADP subscription exists."

		# Check if DPA is ready
		if oc get dataprotectionapplication velero -n "$OADP_NAMESPACE" &>/dev/null; then
			local status
			status=$(oc get dataprotectionapplication velero -n "$OADP_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Reconciled")].status}' 2>/dev/null || echo "")
			if [ "$status" = "True" ]; then
				log_info "OADP is already installed and reconciled."
				return 0
			fi
		fi
	fi

	return 1
}

install_oadp() {
	log_info "Installing OADP operator..."

	# Create namespace
	log_info "Creating namespace..."
	oc apply -f "$YAML_DIR/namespace.yaml"

	# Create OperatorGroup
	log_info "Creating OperatorGroup..."
	oc apply -f "$YAML_DIR/operatorgroup.yaml"

	# Create Subscription
	log_info "Creating Subscription..."
	oc apply -f "$YAML_DIR/subscription.yaml"

	# Wait for operator to be ready
	wait_for_csv "$OADP_NAMESPACE" "redhat-oadp-operator"
}

configure_dpa() {
	log_info "Configuring DataProtectionApplication..."

	# Create cloud credentials secret
	log_info "Creating cloud credentials secret..."
	oc apply -f "$YAML_DIR/cloud-credentials-secret.yaml"

	# Create DPA
	log_info "Creating DataProtectionApplication..."
	oc apply -f "$YAML_DIR/dataprotectionapplication.yaml"

	# Wait for DPA to be ready
	wait_for_dpa
}

check_dpa_reconciled() {
	local status
	status=$(oc get dataprotectionapplication velero -n "$OADP_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Reconciled")].status}')
	[ "$status" = "True" ]
}

wait_for_dpa() {
	log_info "Waiting for DataProtectionApplication to reconcile..."

	if wait_for_condition 60 5 check_dpa_reconciled; then
		log_success "DataProtectionApplication is reconciled!"
	else
		log_error "Timeout waiting for DPA to reconcile."
		log_info "Check status with: oc describe dpa velero -n $OADP_NAMESPACE"
		return 1
	fi
}

verify_installation() {
	log_info "Verifying OADP installation..."
	echo

	log_info "Operator status:"
	oc get csv -n "$OADP_NAMESPACE" -l operators.coreos.com/redhat-oadp-operator.openshift-adp
	echo

	log_info "DataProtectionApplication status:"
	oc get dataprotectionapplication -n "$OADP_NAMESPACE"
	echo

	log_info "Velero pods:"
	oc get pods -n "$OADP_NAMESPACE" -l app.kubernetes.io/name=velero
	echo

	log_info "BackupStorageLocation status:"
	oc get backupstoragelocation -n "$OADP_NAMESPACE"
	echo
}

main() {
	print_header "OADP Operator Installation"
	check_prerequisites

	if check_existing_installation; then
		log_info "OADP already configured, verifying..."
	else
		install_oadp
		configure_dpa
	fi

	verify_installation
	log_success "OADP installation complete!"
}

main
