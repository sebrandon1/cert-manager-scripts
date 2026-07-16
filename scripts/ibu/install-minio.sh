#!/bin/bash

################################################################################
# Script: install-minio.sh
# Description: Install MinIO object storage for OADP backup storage
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/ibu/minio"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"
export MINIO_VERSION="${MINIO_VERSION:-RELEASE.2025-09-07T16-13-09Z}"

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc
	require_cluster
	log_info "Prerequisites check passed."
}

check_existing_installation() {
	log_info "Checking for existing MinIO installation..."

	if check_deployment_exists minio "$MINIO_NAMESPACE"; then
		log_info "MinIO is already installed and running."
		return 0
	fi

	log_info "No existing MinIO installation found."
	return 1
}

install_minio() {
	log_info "Installing MinIO..."

	# Apply resources in order
	log_info "Creating namespace..."
	oc apply -f "$YAML_DIR/namespace.yaml"

	log_info "Creating credentials secret..."
	oc apply -f "$YAML_DIR/secret.yaml"

	log_info "Creating PVC..."
	oc apply -f "$YAML_DIR/pvc.yaml"

	log_info "Creating deployment..."
	oc apply -f "$YAML_DIR/deployment.yaml"

	log_info "Creating service..."
	oc apply -f "$YAML_DIR/service.yaml"

	log_info "Creating console route..."
	oc apply -f "$YAML_DIR/route.yaml"
}

create_velero_bucket() {
	log_info "Creating velero bucket in MinIO..."

	# Use a temporary pod to create the bucket
	oc run minio-mc --rm -i --restart=Never \
		--image=quay.io/minio/mc:latest \
		-n "$MINIO_NAMESPACE" \
		--command -- /bin/sh -c "
			mc alias set myminio http://minio.minio.svc.cluster.local:9000 minio minio123 && \
			mc mb --ignore-existing myminio/velero && \
			echo 'Bucket created successfully'
		" 2>/dev/null || {
		log_warn "Could not create bucket via mc. Will be created on first backup."
	}
}

verify_installation() {
	log_info "Verifying MinIO installation..."
	echo

	log_info "Pod status:"
	oc get pods -n "$MINIO_NAMESPACE"
	echo

	log_info "Service:"
	oc get service minio -n "$MINIO_NAMESPACE"
	echo

	local route_host
	route_host=$(oc get route minio-console -n "$MINIO_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

	if [ -n "$route_host" ]; then
		log_info "MinIO Console URL: https://${route_host}"
		log_info "Login with: minio / minio123"
	fi
	echo

	log_info "Internal S3 endpoint: http://minio.minio.svc.cluster.local:9000"
}

main() {
	print_header "MinIO Object Storage Installation"
	check_prerequisites

	if check_existing_installation; then
		log_info "Verifying existing installation..."
	else
		install_minio
		wait_for_resource "deployment/minio" "$MINIO_NAMESPACE" "${DEPLOYMENT_READY_TIMEOUT:-300s}"
		create_velero_bucket
	fi

	verify_installation
	log_success "MinIO installation complete!"
}

main
