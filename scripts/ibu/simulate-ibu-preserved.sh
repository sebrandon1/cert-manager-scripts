#!/bin/bash

################################################################################
# Script: simulate-ibu-preserved.sh
# Description: Simulate IBU with certificate preservation using LCA-style backup
#              Uses lca.openshift.io/apply-label annotation to preserve specific
#              cert-manager resources during backup/restore.
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/ibu/backup"
OADP_NAMESPACE="${OADP_NAMESPACE:-openshift-adp}"

# Configuration
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
export BACKUP_NAME="${BACKUP_NAME:-ibu-preserved-$(date +%s)}"
export RESTORE_NAME="${RESTORE_NAME:-${BACKUP_NAME}-restore}"

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc jq envsubst
	require_cluster

	# Check OADP is ready
	if ! oc get dataprotectionapplication velero -n "$OADP_NAMESPACE" &>/dev/null; then
		log_error "OADP is not installed. Run 'make install-oadp' first."
		exit 1
	fi

	# Check backup storage location is available
	local bsl_phase
	bsl_phase=$(oc get backupstoragelocation -n "$OADP_NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
	if [ "$bsl_phase" != "Available" ]; then
		log_error "BackupStorageLocation is not available (phase: $bsl_phase)"
		exit 1
	fi

	# Check for labeled certificates
	local labeled_certs
	labeled_certs=$(oc get certificates -n "$TARGET_NAMESPACE" -l "lca.openshift.io/backup" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [ "$labeled_certs" -eq 0 ]; then
		log_error "No labeled certificates found. Run label-cert-resources.sh first."
		exit 1
	fi

	log_info "Found $labeled_certs labeled certificates."
	log_info "Prerequisites check passed."
}

create_preserved_backup() {
	log_info "Creating preserved backup: $BACKUP_NAME"

	# Build the apply-label annotation
	local apply_label_annotation
	apply_label_annotation=$(build_lca_annotations "$TARGET_NAMESPACE")

	log_info "Using apply-label annotation: $apply_label_annotation"

	apply_yaml_template "$YAML_DIR/backup-preserved.yaml" "Backup"

	# Wait for backup to complete
	wait_for_backup_restore "backup" "$BACKUP_NAME" "$OADP_NAMESPACE"
}

delete_namespace_resources() {
	log_info "Simulating IBU: Deleting certificate resources in $TARGET_NAMESPACE..."

	# Delete certificates (but preserve labels by noting them)
	log_info "Deleting certificates..."
	oc delete certificates --all -n "$TARGET_NAMESPACE" --ignore-not-found=true

	# Delete certificate requests
	log_info "Deleting certificate requests..."
	oc delete certificaterequests --all -n "$TARGET_NAMESPACE" --ignore-not-found=true

	# Delete TLS secrets
	log_info "Deleting TLS secrets..."
	oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null |
		jq -r '.items | map(select(.type == "kubernetes.io/tls")) | .[].metadata.name' |
		while read -r secret_name; do
			if [ -n "$secret_name" ]; then
				oc delete secret "$secret_name" -n "$TARGET_NAMESPACE" --ignore-not-found=true
			fi
		done

	log_info "Resources deleted. This simulates what happens during IBU."
}

restore_from_backup() {
	log_info "Restoring from preserved backup: $BACKUP_NAME"

	apply_yaml_template "$YAML_DIR/restore-preserved.yaml" "Restore"

	# Wait for restore to complete
	wait_for_backup_restore "restore" "$RESTORE_NAME" "$OADP_NAMESPACE"
}

verify_restored_resources() {
	log_info "Verifying restored resources..."

	# Check certificates were restored
	local cert_count
	cert_count=$(oc get certificates -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	log_info "Restored certificates: $cert_count"

	# Check secrets were restored
	local secret_count
	secret_count=$(oc get secrets -n "$TARGET_NAMESPACE" -o json 2>/dev/null |
		jq -r '.items | map(select(.type == "kubernetes.io/tls")) | length')
	log_info "Restored TLS secrets: $secret_count"

	# Verify certificate status
	log_info "Certificate status after restore:"
	oc get certificates -n "$TARGET_NAMESPACE" -o wide
}

print_summary() {
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  IBU Preserved Simulation Complete"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
	echo "  Backup:   $BACKUP_NAME"
	echo "  Restore:  $RESTORE_NAME"
	echo "  Mode:     Certificate Preservation (LCA-style)"
	echo
	echo "  The simulation performed:"
	echo "  1. Backed up labeled certificates and secrets (with raw data)"
	echo "  2. Deleted all certificates and TLS secrets"
	echo "  3. Restored from backup (including original cert data)"
	echo
	echo "  Next step: Validate that certificates were preserved"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
}

main() {
	print_header "IBU Simulation (Preserved Mode)"
	log_info "Target Namespace: $TARGET_NAMESPACE"
	log_info "Backup Name: $BACKUP_NAME"
	log_info "Mode: Certificate Preservation"
	echo

	check_prerequisites

	create_preserved_backup
	delete_namespace_resources
	restore_from_backup
	verify_restored_resources

	print_summary
	log_success "IBU preserved simulation complete!"
}

main
