#!/bin/bash

################################################################################
# Script: run-ibu-preserved-test.sh
# Description: Scenario 2 - IBU certificate PRESERVATION testing
#              Validates that certificates CAN be preserved during IBU
#              when properly labeled using lca.openshift.io/apply-label annotation.
#
#              Test workflow:
#              1. Create test certificate (if needed)
#              2. Label resources for preservation
#              3. Capture pre-IBU state
#              4. Simulate IBU with labeled backup
#              5. Capture post-IBU state
#              6. Validate certificates were PRESERVED (checksums match)
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Configuration
export STATE_DIR="${STATE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ibu-cert-state.XXXXXX")}"
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
export BACKUP_NAME="${BACKUP_NAME:-ibu-preserved-$(date +%s)}"
export RESTORE_NAME="${RESTORE_NAME:-${BACKUP_NAME}-restore}"
MULTI_ALGO="${MULTI_ALGO:-false}"

print_banner() {
	echo
	echo "╔═══════════════════════════════════════════════════════════════╗"
	echo "║       IBU Certificate PRESERVATION Test (Scenario 2)         ║"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo
	echo "  This test validates that cert-manager certificates CAN BE"
	echo "  preserved during IBU when using lca.openshift.io/apply-label."
	echo
	echo "  Target namespace: $TARGET_NAMESPACE"
	echo "  State directory:  $STATE_DIR"
	echo "  Backup name:      $BACKUP_NAME"
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
			log_info "Creating test certificate..."
			create_test_certificate
		fi
	fi

	log_success "All prerequisites met!"
}

create_test_certificate() {
	log_info "Creating test certificate for IBU preservation validation..."
	create_ibu_test_certificate "$TARGET_NAMESPACE"
}

label_resources_for_preservation() {
	log_info "Step 1/5: Labeling resources for preservation..."
	echo

	"$SCRIPT_DIR/label-cert-resources.sh"
}

capture_before_state() {
	log_info "Step 2/5: Capturing pre-IBU certificate state..."
	echo

	STATE_LABEL=before "$SCRIPT_DIR/capture-cert-state.sh"
}

simulate_ibu_preserved() {
	log_info "Step 3/5: Simulating IBU with preserved backup..."
	echo

	"$SCRIPT_DIR/simulate-ibu-preserved.sh"
}

capture_after_state() {
	log_info "Step 4/5: Capturing post-IBU certificate state..."
	echo

	log_info "Waiting for resources to stabilize..."
	retry 6 5 oc wait --for=condition=Ready certificates --all -n "$TARGET_NAMESPACE" --timeout=5s

	STATE_LABEL=after "$SCRIPT_DIR/capture-cert-state.sh"
}

validate_results() {
	log_info "Step 5/5: Validating certificate preservation..."
	echo

	"$SCRIPT_DIR/validate-cert-loss.sh" --expect-preserved
}

cleanup_state() {
	if [ -d "$STATE_DIR" ]; then
		log_info "Cleaning up state directory..."
		rm -rf "$STATE_DIR"
	fi
}

print_final_summary() {
	echo
	echo "╔═══════════════════════════════════════════════════════════════╗"
	echo "║       IBU Certificate Preservation Test Complete              ║"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo
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

	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  Starting IBU Certificate Preservation Test"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo

	label_resources_for_preservation
	capture_before_state
	simulate_ibu_preserved
	capture_after_state
	validate_results

	print_final_summary
}

main "$@"
