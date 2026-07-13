#!/bin/bash

################################################################################
# Script: run-ibu-test.sh
# Description: Main orchestration script for IBU certificate loss testing
#              Runs the complete test workflow:
#              1. Verify prerequisites (cert-manager, OADP, MinIO)
#              2. Capture pre-IBU certificate state
#              3. Simulate IBU via OADP backup/restore
#              4. Capture post-IBU certificate state
#              5. Validate certificate loss
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
setup_cleanup

# Configuration
export STATE_DIR="${STATE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ibu-cert-state.XXXXXX")}"
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
MULTI_ALGO="${MULTI_ALGO:-false}"

print_banner() {
	print_header "IBU Certificate Loss Validation Test"
	echo "  This test validates that cert-manager certificates are NOT"
	echo "  preserved during Image-Based Upgrade (IBU) operations."
	echo
	echo "  Target namespace: $TARGET_NAMESPACE"
	echo "  State directory:  $STATE_DIR"
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_ibu_prereqs

	local cert_count
	cert_count=$(oc get certificates -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [ "$cert_count" -eq 0 ]; then
		log_warn "No certificates found in namespace $TARGET_NAMESPACE"
		if [ "$MULTI_ALGO" = "true" ]; then
			log_info "Creating multi-algorithm test certificates..."
			"$SCRIPT_DIR/create-multi-algo-certs.sh"
		else
			log_info "Creating test certificate using existing setup..."
			create_test_certificate
		fi
	fi

	log_success "All prerequisites met!"
}

create_test_certificate() {
	log_info "Creating test certificate for IBU validation..."
	create_ibu_test_certificate "$TARGET_NAMESPACE"
}

capture_before_state() {
	log_info "Step 1/4: Capturing pre-IBU certificate state..."
	echo

	STATE_LABEL=before "$SCRIPT_DIR/capture-cert-state.sh"
}

simulate_ibu() {
	log_info "Step 2/4: Simulating IBU via OADP backup/restore..."
	echo

	"$SCRIPT_DIR/simulate-ibu-backup-restore.sh"
}

capture_after_state() {
	log_info "Step 3/4: Capturing post-IBU certificate state..."
	echo

	log_info "Waiting for cert-manager to reconcile certificates..."
	retry 12 5 oc wait --for=condition=Ready certificates --all -n "$TARGET_NAMESPACE" --timeout=5s

	STATE_LABEL=after "$SCRIPT_DIR/capture-cert-state.sh"
}

validate_results() {
	log_info "Step 4/4: Validating certificate loss..."
	echo

	"$SCRIPT_DIR/validate-cert-loss.sh"
}

cleanup_state() {
	if [ -d "$STATE_DIR" ]; then
		log_info "Cleaning up state directory..."
		rm -rf "$STATE_DIR"
	fi
}

print_final_summary() {
	print_header "IBU Certificate Loss Test Complete"
	echo "  State files preserved in: $STATE_DIR"
	echo
	echo "  To review results:"
	echo "    cat $STATE_DIR/validation-results.json | jq ."
	echo
	echo "  To clean up test resources:"
	echo "    make clean-ibu"
	echo
}

main() {
	# Clean up previous state
	cleanup_state

	print_banner
	check_prerequisites

	print_header "Starting IBU Certificate Loss Test"

	capture_before_state
	simulate_ibu
	capture_after_state
	validate_results

	print_final_summary
}

main "$@"
