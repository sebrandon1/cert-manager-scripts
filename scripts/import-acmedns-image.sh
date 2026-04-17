#!/bin/bash

################################################################################
# Script: import-acmedns-image.sh
# Description: Import acme-dns image for air-gapped clusters
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

print_header "Import acme-dns Image"

ACMEDNS_IMAGE="joohoi/acme-dns:latest"
ACMEDNS_NAMESPACE="${ACMEDNS_NAMESPACE:-acme-dns}"

log_info "Checking if we can pull the image locally..."

# Try to pull with podman first, then docker
if command -v podman &>/dev/null; then
	CONTAINER_CMD="podman"
elif command -v docker &>/dev/null; then
	CONTAINER_CMD="docker"
else
	log_error "Neither podman nor docker found. Please install one."
	exit 1
fi

log_info "Using $CONTAINER_CMD to pull image..."

if ! $CONTAINER_CMD pull $ACMEDNS_IMAGE; then
	log_error "Failed to pull image. Check your internet connection."
	exit 1
fi

log_info "Image pulled successfully. Saving to tar file..."
$CONTAINER_CMD save $ACMEDNS_IMAGE -o /tmp/acme-dns.tar

log_info "Importing image to CRC/OpenShift..."

# For CRC, we can use crc podman-env or import to internal registry
if command -v crc &>/dev/null && crc status | grep -q "Running"; then
	log_info "Detected CRC. Importing to CRC's podman..."
	eval $(crc podman-env)
	podman load -i /tmp/acme-dns.tar
	log_info "Image imported to CRC!"
else
	log_warn "Not using CRC or CRC not running."
	log_info "Attempting to push to OpenShift internal registry..."

	# Get internal registry
	REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

	if [ -z "$REGISTRY" ]; then
		log_error "Could not find OpenShift internal registry."
		log_info "Manual steps:"
		log_info "1. Load image: $CONTAINER_CMD load -i /tmp/acme-dns.tar"
		log_info "2. Tag for your registry"
		log_info "3. Push to your registry"
		exit 1
	fi

	# Tag and push
	NEW_TAG="${REGISTRY}/${ACMEDNS_NAMESPACE}/acme-dns:latest"
	log_info "Tagging image as: $NEW_TAG"
	$CONTAINER_CMD tag $ACMEDNS_IMAGE $NEW_TAG

	log_info "Logging into internal registry..."
	$CONTAINER_CMD login -u kubeadmin -p $(oc whoami -t) $REGISTRY

	log_info "Pushing image..."
	$CONTAINER_CMD push $NEW_TAG

	log_info "Image pushed to internal registry!"
	log_info "Update your deployment to use: $NEW_TAG"
fi

rm -f /tmp/acme-dns.tar
log_info "Cleanup complete!"
echo
log_info "Next step: Re-run install-local-dns.sh"
