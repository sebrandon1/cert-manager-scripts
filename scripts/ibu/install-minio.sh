#!/bin/bash

################################################################################
# Script: install-minio.sh
# Description: Install MinIO object storage for OADP backup storage
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/ibu/minio"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"
# MinIO is source-only upstream (repos archived); these are the final release tags.
export MINIO_VERSION="${MINIO_VERSION:-RELEASE.2025-10-15T17-29-55Z}"
export MINIO_MC_VERSION="${MINIO_MC_VERSION:-RELEASE.2025-08-13T08-35-41Z}"
MINIO_BUILT_IMAGE="image-registry.openshift-image-registry.svc:5000/${MINIO_NAMESPACE}/minio:${MINIO_VERSION}"
# Set MINIO_IMAGE to a pre-built image (e.g. a mirror) to skip the in-cluster build.
export MINIO_IMAGE="${MINIO_IMAGE:-$MINIO_BUILT_IMAGE}"
MINIO_MC_IMAGE="${MINIO_MC_IMAGE:-$MINIO_IMAGE}"
export MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minio}"
export MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minio123}"

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

build_minio_image() {
	if [[ "$MINIO_IMAGE" != "$MINIO_BUILT_IMAGE" ]]; then
		log_info "Using MINIO_IMAGE=$MINIO_IMAGE; skipping in-cluster build."
		return 0
	fi

	if ! "$KUBE_CLI" api-resources --api-group=build.openshift.io -o name 2>/dev/null | grep -q '^buildconfigs\.'; then
		log_error "The OpenShift Build API is not available, so MinIO cannot be built in-cluster."
		log_hint "Set MINIO_IMAGE (and MINIO_MC_IMAGE if it lacks mc) to a pre-built MinIO image"
		return 1
	fi

	apply_yaml_template "$YAML_DIR/imagestream.yaml" "MinIO ImageStream"
	apply_yaml_template "$YAML_DIR/buildconfig.yaml" "MinIO BuildConfig"

	if "$KUBE_CLI" get istag "minio:${MINIO_VERSION}" -n "$MINIO_NAMESPACE" &>/dev/null; then
		log_info "MinIO image minio:${MINIO_VERSION} already built; skipping build."
		return 0
	fi

	log_info "Building MinIO ${MINIO_VERSION} and mc ${MINIO_MC_VERSION} from source (this can take several minutes)..."
	if ! "$KUBE_CLI" start-build minio -n "$MINIO_NAMESPACE" --follow --wait; then
		log_error "MinIO image build failed."
		# Capture the reason before the rollback deletes the namespace.
		"$KUBE_CLI" get builds -n "$MINIO_NAMESPACE" \
			-o custom-columns='NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message' || true
		"$KUBE_CLI" get pods -n "$MINIO_NAMESPACE" -l openshift.io/build.name \
			-o custom-columns='POD:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[*].state.terminated.reason' || true
		"$KUBE_CLI" get events -n "$MINIO_NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | tail -15 || true
		"$KUBE_CLI" describe node 2>/dev/null | grep -A6 '^Conditions:' || true
		log_hint "Set MINIO_IMAGE to a pre-built image to skip the in-cluster build"
		return 1
	fi
	log_success "MinIO image built: $MINIO_BUILT_IMAGE"
}

install_minio() {
	log_info "Installing MinIO..."

	# A failed earlier attempt's rollback deletes the namespace without waiting;
	# applying into a terminating namespace is rejected, so let it finish first.
	if [[ "$("$KUBE_CLI" get namespace "$MINIO_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Terminating" ]]; then
		log_info "Waiting for namespace $MINIO_NAMESPACE to finish terminating..."
		"$KUBE_CLI" wait --for=delete "namespace/$MINIO_NAMESPACE" --timeout=300s
	fi

	# Apply resources in order
	apply_yaml_template "$YAML_DIR/namespace.yaml" "MinIO namespace"
	register_rollback "$KUBE_CLI" delete namespace "$MINIO_NAMESPACE" --ignore-not-found=true --wait=false

	build_minio_image

	apply_yaml_template "$YAML_DIR/secret.yaml" "MinIO credentials secret"

	apply_yaml_template "$YAML_DIR/pvc.yaml" "MinIO PVC"

	apply_yaml_template "$YAML_DIR/deployment.yaml" "MinIO deployment"

	apply_yaml_template "$YAML_DIR/service.yaml" "MinIO service"

	apply_yaml_template "$YAML_DIR/route.yaml" "MinIO console route"
}

create_velero_bucket() {
	log_info "Creating velero bucket in MinIO..."

	# Use a temporary pod to create the bucket
	# Velero does not create buckets, so OADP cannot work without this one.
	if ! "$KUBE_CLI" run minio-mc --rm -i --restart=Never \
		--image="$MINIO_MC_IMAGE" \
		--env=HOME=/tmp \
		-n "$MINIO_NAMESPACE" \
		--command -- /bin/sh -c "
			mc alias set myminio http://minio.minio.svc.cluster.local:9000 ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} && \
			mc mb --ignore-existing myminio/velero && \
			echo 'Bucket created successfully'
		"; then
		log_error "Could not create the velero bucket via mc."
		log_hint "MINIO_MC_IMAGE ($MINIO_MC_IMAGE) must provide the mc client"
		return 1
	fi
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
		log_info "Login with: ${MINIO_ACCESS_KEY} / ${MINIO_SECRET_KEY}"
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
	clear_rollback
}

main
