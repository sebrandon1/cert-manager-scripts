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

	local labeled=0
	while IFS= read -r cert_name; do
		[[ -z "$cert_name" ]] && continue
		log_info "  Labeling certificate: $cert_name"
		oc label certificate "$cert_name" -n "$TARGET_NAMESPACE" \
			"lca.openshift.io/backup=$BACKUP_NAME" \
			--overwrite 2>/dev/null || true
		labeled=$((labeled + 1))
	done < <(oc get certificates -n "$TARGET_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

	log_success "Labeled $labeled certificates"
}

label_secrets() {
	log_info "Labeling TLS secrets with lca.openshift.io/backup=$BACKUP_NAME..."

	local labeled=0
	while IFS= read -r secret_name; do
		[[ -z "$secret_name" ]] && continue
		log_info "  Labeling secret: $secret_name"
		oc label secret "$secret_name" -n "$TARGET_NAMESPACE" \
			"lca.openshift.io/backup=$BACKUP_NAME" \
			--overwrite 2>/dev/null || true
		labeled=$((labeled + 1))
	done < <(oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null |
		jq -r '.items | map(select(.type == "kubernetes.io/tls")) | .[].metadata.name')

	log_success "Labeled $labeled TLS secrets"
}

print_labeling_summary() {
	print_header "Resource Labeling Complete"
	echo "  Labeled resources with: lca.openshift.io/backup=$BACKUP_NAME"
	echo
	echo "  These resources will be preserved during IBU when using"
	echo "  a Backup CR with the lca.openshift.io/apply-label annotation."
	echo
	echo "  Verify labels:"
	echo "    oc get certificates -n $TARGET_NAMESPACE --show-labels"
	echo "    oc get secrets -n $TARGET_NAMESPACE --show-labels"
	echo
}

main() {
	print_header "LCA Resource Labeling"
	log_info "Target Namespace: $TARGET_NAMESPACE"
	log_info "Backup Name: $BACKUP_NAME"
	echo

	check_prerequisites

	label_certificates
	label_secrets

	# Output the annotation value for use in backup CRs
	local annotation_value
	annotation_value=$(build_lca_annotations "$TARGET_NAMESPACE")

	echo
	log_info "Annotation value for Backup CR:"
	echo "  lca.openshift.io/apply-label: $annotation_value"

	print_labeling_summary
	log_success "Resource labeling complete!"
}

main "$@"
