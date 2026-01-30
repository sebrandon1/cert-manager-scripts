#!/bin/bash

################################################################################
# Script: label-cert-resources.sh
# Description: Apply LCA labels to cert-manager resources for preservation
#              during IBU. The lca.openshift.io/backup label tells the
#              Lifecycle Agent which resources to preserve.
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
BACKUP_NAME="${BACKUP_NAME:-ibu-preserved-backup}"

print_header() {
	echo
	echo "========================================"
	echo "  LCA Resource Labeling"
	echo "========================================"
	echo
	echo "  Target Namespace: $TARGET_NAMESPACE"
	echo "  Backup Name:      $BACKUP_NAME"
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc jq
	require_cluster

	# Check for certificates in target namespace
	local cert_count
	cert_count=$(oc get certificates -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [ "$cert_count" -eq 0 ]; then
		log_error "No certificates found in namespace $TARGET_NAMESPACE"
		exit 1
	fi

	log_info "Found $cert_count certificates to label."
}

label_certificates() {
	log_info "Labeling Certificate CRs with lca.openshift.io/backup=$BACKUP_NAME..."

	local cert_names
	cert_names=$(oc get certificates -n "$TARGET_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

	local labeled=0
	for cert_name in $cert_names; do
		log_info "  Labeling certificate: $cert_name"
		oc label certificate "$cert_name" -n "$TARGET_NAMESPACE" \
			"lca.openshift.io/backup=$BACKUP_NAME" \
			--overwrite 2>/dev/null || true
		labeled=$((labeled + 1))
	done

	log_success "Labeled $labeled certificates"
}

label_secrets() {
	log_info "Labeling TLS secrets with lca.openshift.io/backup=$BACKUP_NAME..."

	# Get TLS secrets (type kubernetes.io/tls)
	local secret_names
	secret_names=$(oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null |
		jq -r '.items | map(select(.type == "kubernetes.io/tls")) | .[].metadata.name')

	local labeled=0
	for secret_name in $secret_names; do
		log_info "  Labeling secret: $secret_name"
		oc label secret "$secret_name" -n "$TARGET_NAMESPACE" \
			"lca.openshift.io/backup=$BACKUP_NAME" \
			--overwrite 2>/dev/null || true
		labeled=$((labeled + 1))
	done

	log_success "Labeled $labeled TLS secrets"
}

build_annotation_list() {
	log_info "Building lca.openshift.io/apply-label annotation value..."

	local annotation_parts=()

	# Get all certificates
	local cert_names
	cert_names=$(oc get certificates -n "$TARGET_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

	for cert_name in $cert_names; do
		# Add certificate
		annotation_parts+=("cert-manager.io/v1/certificates/$TARGET_NAMESPACE/$cert_name")

		# Get the associated secret name
		local secret_name
		secret_name=$(oc get certificate "$cert_name" -n "$TARGET_NAMESPACE" \
			-o jsonpath='{.spec.secretName}' 2>/dev/null || echo "")

		if [ -n "$secret_name" ]; then
			# Check if secret exists
			if oc get secret "$secret_name" -n "$TARGET_NAMESPACE" &>/dev/null; then
				annotation_parts+=("v1/secrets/$TARGET_NAMESPACE/$secret_name")
			fi
		fi
	done

	# Join with commas
	local annotation_value
	annotation_value=$(
		IFS=','
		echo "${annotation_parts[*]}"
	)

	echo "$annotation_value"
}

print_summary() {
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  Resource Labeling Complete"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
	echo "  Labeled resources with: lca.openshift.io/backup=$BACKUP_NAME"
	echo
	echo "  These resources will be preserved during IBU when using"
	echo "  a Backup CR with the lca.openshift.io/apply-label annotation."
	echo
	echo "  Verify labels:"
	echo "    oc get certificates -n $TARGET_NAMESPACE --show-labels"
	echo "    oc get secrets -n $TARGET_NAMESPACE --show-labels"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
}

main() {
	print_header
	check_prerequisites

	label_certificates
	label_secrets

	# Output the annotation value for use in backup CRs
	local annotation_value
	annotation_value=$(build_annotation_list)

	echo
	log_info "Annotation value for Backup CR:"
	echo "  lca.openshift.io/apply-label: $annotation_value"

	print_summary
	log_success "Resource labeling complete!"
}

main "$@"
