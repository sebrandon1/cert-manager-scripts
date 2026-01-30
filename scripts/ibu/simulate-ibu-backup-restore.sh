#!/bin/bash

################################################################################
# Script: simulate-ibu-backup-restore.sh
# Description: Simulate IBU behavior using OADP backup/restore cycle
#              This tests certificate persistence by:
#              1. Creating a backup of the target namespace
#              2. Deleting certificate resources
#              3. Restoring from backup
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/ibu/backup"
OADP_NAMESPACE="${OADP_NAMESPACE:-openshift-adp}"

# Configuration
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
export BACKUP_NAME="${BACKUP_NAME:-ibu-cert-test-$(date +%s)}"
export RESTORE_NAME="${RESTORE_NAME:-${BACKUP_NAME}-restore}"

print_header() {
	echo
	echo "========================================"
	echo "  IBU Simulation via OADP"
	echo "========================================"
	echo
	echo "  Target Namespace: $TARGET_NAMESPACE"
	echo "  Backup Name:      $BACKUP_NAME"
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd oc envsubst
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
		log_info "Check MinIO and OADP configuration."
		exit 1
	fi

	# Check for certificates in target namespace
	local cert_count
	cert_count=$(oc get certificates -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
	if [ "$cert_count" -eq 0 ]; then
		log_error "No certificates found in namespace $TARGET_NAMESPACE"
		log_info "Create test certificates first using existing Pebble setup."
		exit 1
	fi

	log_info "Prerequisites check passed."
}

create_backup() {
	log_info "Creating backup: $BACKUP_NAME"

	# Apply backup CR with variable substitution
	envsubst <"$YAML_DIR/backup.yaml" | oc apply -f -

	# Wait for backup to complete
	log_info "Waiting for backup to complete..."
	local max_attempts=60
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		local phase
		phase=$(oc get backup "$BACKUP_NAME" -n "$OADP_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

		case "$phase" in
		Completed)
			log_success "Backup completed successfully!"
			return 0
			;;
		Failed | PartiallyFailed)
			log_error "Backup failed with phase: $phase"
			oc describe backup "$BACKUP_NAME" -n "$OADP_NAMESPACE"
			return 1
			;;
		esac

		attempt=$((attempt + 1))
		if [ $((attempt % 6)) -eq 0 ]; then
			log_info "Backup phase: $phase ($attempt/$max_attempts)"
		fi
		sleep 5
	done

	log_error "Timeout waiting for backup to complete"
	return 1
}

delete_namespace_resources() {
	log_info "Simulating IBU: Deleting certificate resources in $TARGET_NAMESPACE..."

	# Delete certificates
	log_info "Deleting certificates..."
	oc delete certificates --all -n "$TARGET_NAMESPACE" --ignore-not-found=true

	# Delete certificate requests
	log_info "Deleting certificate requests..."
	oc delete certificaterequests --all -n "$TARGET_NAMESPACE" --ignore-not-found=true

	# Delete TLS secrets (those created by cert-manager)
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
	log_info "Restoring from backup: $BACKUP_NAME"

	# Apply restore CR with variable substitution
	envsubst <"$YAML_DIR/restore.yaml" | oc apply -f -

	# Wait for restore to complete
	log_info "Waiting for restore to complete..."
	local max_attempts=60
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		local phase
		phase=$(oc get restore "$RESTORE_NAME" -n "$OADP_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

		case "$phase" in
		Completed)
			log_success "Restore completed successfully!"
			return 0
			;;
		Failed | PartiallyFailed)
			log_error "Restore failed with phase: $phase"
			oc describe restore "$RESTORE_NAME" -n "$OADP_NAMESPACE"
			return 1
			;;
		esac

		attempt=$((attempt + 1))
		if [ $((attempt % 6)) -eq 0 ]; then
			log_info "Restore phase: $phase ($attempt/$max_attempts)"
		fi
		sleep 5
	done

	log_error "Timeout waiting for restore to complete"
	return 1
}

wait_for_cert_manager_reconcile() {
	log_info "Waiting for cert-manager to reconcile certificates..."

	# Delete restored CertificateRequests to allow cert-manager to create new ones
	# The restored CRs have stale data and block new certificate issuance
	log_info "Cleaning up restored CertificateRequests..."
	oc delete certificaterequests --all -n "$TARGET_NAMESPACE" --ignore-not-found=true 2>/dev/null || true

	# Wait for cert-manager to process
	sleep 30

	# Check certificate status
	log_info "Current certificate status:"
	oc get certificates -n "$TARGET_NAMESPACE"
}

print_summary() {
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  IBU Simulation Complete"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
	echo "  Backup:   $BACKUP_NAME"
	echo "  Restore:  $RESTORE_NAME"
	echo
	echo "  The simulation performed:"
	echo "  1. Backed up certificates and secrets"
	echo "  2. Deleted all certificates and TLS secrets"
	echo "  3. Restored from backup"
	echo
	echo "  Next step: Run validate-cert-loss.sh to compare states"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
}

main() {
	print_header
	check_prerequisites

	create_backup
	delete_namespace_resources
	restore_from_backup
	wait_for_cert_manager_reconcile

	print_summary
	log_success "IBU simulation complete!"
}

main
