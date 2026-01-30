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
export STATE_DIR="${STATE_DIR:-/tmp/ibu-cert-state}"
export TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"
export BACKUP_NAME="${BACKUP_NAME:-ibu-preserved-$(date +%s)}"
export RESTORE_NAME="${RESTORE_NAME:-${BACKUP_NAME}-restore}"

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

	require_cmd oc jq envsubst

	# Check cluster connectivity
	require_cluster

	# Check cert-manager is installed
	if ! oc get deployment cert-manager -n cert-manager &>/dev/null; then
		log_error "cert-manager is not installed."
		log_info "Run 'make install-cert-manager-operator' first."
		exit 1
	fi

	# Check OADP is installed
	if ! oc get dataprotectionapplication velero -n openshift-adp &>/dev/null; then
		log_error "OADP is not installed."
		log_info "Run 'make install-ibu-prereqs' first."
		exit 1
	fi

	# Check MinIO is running
	if ! oc get deployment minio -n minio &>/dev/null; then
		log_error "MinIO is not installed."
		log_info "Run 'make install-minio' first."
		exit 1
	fi

	# Check for test certificates
	local cert_count
	cert_count=$(oc get certificates -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [ "$cert_count" -eq 0 ]; then
		log_warn "No certificates found in namespace $TARGET_NAMESPACE"
		log_info "Creating test certificate..."
		create_test_certificate
	fi

	log_success "All prerequisites met!"
}

create_test_certificate() {
	log_info "Creating test certificate for IBU preservation validation..."

	local issuer="selfsigned-issuer"

	# Create selfsigned issuer if it doesn't exist
	if ! oc get clusterissuer "$issuer" &>/dev/null; then
		log_info "Creating selfsigned ClusterIssuer..."
		cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
	fi

	# Create a test certificate with preservation label
	cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ibu-test-cert
  namespace: $TARGET_NAMESPACE
  labels:
    app: ibu-test
spec:
  secretName: ibu-test-cert-tls
  issuerRef:
    name: $issuer
    kind: ClusterIssuer
  dnsNames:
    - ibu-test.example.com
    - "*.ibu-test.example.com"
  duration: 8760h
EOF

	# Wait for certificate to be ready
	log_info "Waiting for certificate to be issued..."
	local max_attempts=30
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		local ready
		ready=$(oc get certificate ibu-test-cert -n "$TARGET_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

		if [ "$ready" = "True" ]; then
			log_success "Test certificate is ready!"
			return 0
		fi

		attempt=$((attempt + 1))
		sleep 2
	done

	log_error "Timeout waiting for test certificate"
	exit 1
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

	# Wait for resources to stabilize
	log_info "Waiting for resources to stabilize..."
	sleep 15

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
