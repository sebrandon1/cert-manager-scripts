#!/bin/bash

################################################################################
# Script: validate-cert-loss.sh
# Description: Compare before/after certificate states to validate
#              certificate behavior during IBU simulation.
#
# Usage:
#   validate-cert-loss.sh                    # Expect certs to be LOST (Scenario 1)
#   validate-cert-loss.sh --expect-preserved # Expect certs to be PRESERVED (Scenario 2)
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Configuration
STATE_DIR="${STATE_DIR:-/tmp/ibu-cert-state}"
EXPECT_PRESERVED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--expect-preserved)
		EXPECT_PRESERVED=true
		shift
		;;
	*)
		log_warn "Unknown argument: $1"
		shift
		;;
	esac
done

print_validation_header() {
	if [ "$EXPECT_PRESERVED" = true ]; then
		print_header "IBU Certificate Preservation Validation"
	else
		print_header "IBU Certificate Loss Validation"
	fi
	if [ "$EXPECT_PRESERVED" = true ]; then
		echo "  Mode: Expecting certificates to be PRESERVED"
	else
		echo "  Mode: Expecting certificates to be LOST"
	fi
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."
	require_cmd jq

	# Check state files exist
	if [ ! -f "$STATE_DIR/checksums-before.json" ]; then
		log_error "Before state not found. Run 'capture-cert-state.sh' with STATE_LABEL=before first."
		exit 1
	fi

	if [ ! -f "$STATE_DIR/checksums-after.json" ]; then
		log_error "After state not found. Run 'capture-cert-state.sh' with STATE_LABEL=after first."
		exit 1
	fi

	log_info "State files found."
}

compare_checksums() {
	local before_file="$STATE_DIR/checksums-before.json"
	local after_file="$STATE_DIR/checksums-after.json"
	local results_file="$STATE_DIR/validation-results.json"

	# Initialize results
	local total=0
	local changed=0
	local unchanged=0
	local missing=0
	local results="[]"

	# Compare each secret from before
	while IFS= read -r secret_name; do
		[[ -z "$secret_name" ]] && continue
		total=$((total + 1))

		# Get before checksum
		local before_cert_checksum
		before_cert_checksum=$(jq -r --arg name "$secret_name" '.[] | select(.name == $name) | .cert_checksum' "$before_file")

		# Get after checksum
		local after_cert_checksum
		after_cert_checksum=$(jq -r --arg name "$secret_name" '.[] | select(.name == $name) | .cert_checksum // "MISSING"' "$after_file")

		local status
		if [ "$after_cert_checksum" = "MISSING" ] || [ -z "$after_cert_checksum" ]; then
			status="MISSING"
			missing=$((missing + 1))
		elif [ "$before_cert_checksum" = "$after_cert_checksum" ]; then
			status="UNCHANGED"
			unchanged=$((unchanged + 1))
		else
			status="CHANGED"
			changed=$((changed + 1))
		fi

		# Add to results
		results=$(echo "$results" | jq --arg name "$secret_name" \
			--arg before "$before_cert_checksum" \
			--arg after "$after_cert_checksum" \
			--arg status "$status" \
			'. += [{name: $name, before_checksum: $before, after_checksum: $after, status: $status}]')

		# Print comparison to stderr so it doesn't interfere with return value
		echo "  $secret_name:" >&2
		echo "    Before: ${before_cert_checksum:0:16}..." >&2
		echo "    After:  ${after_cert_checksum:0:16}..." >&2
		echo "    Status: $status" >&2
		echo >&2
	done < <(jq -r '.[].name' "$before_file")

	# Save results
	cat >"$results_file" <<EOF
{
	"timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
	"summary": {
		"total": $total,
		"changed": $changed,
		"unchanged": $unchanged,
		"missing": $missing
	},
	"details": $results
}
EOF

	# Return results (only this goes to stdout)
	echo "$changed,$unchanged,$missing,$total"
}

print_report() {
	local changed=$1
	local unchanged=$2
	local missing=$3
	local total=$4

	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	if [ "$EXPECT_PRESERVED" = true ]; then
		echo "  IBU Certificate Preservation Validation Report"
	else
		echo "  IBU Certificate Loss Validation Report"
	fi
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo
	printf "  %-25s %s\n" "Total Secrets Compared:" "$total"
	printf "  %-25s %s\n" "Changed (New Certs):" "$changed"
	printf "  %-25s %s\n" "Unchanged (Same Certs):" "$unchanged"
	printf "  %-25s %s\n" "Missing:" "$missing"
	echo
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo

	# Determine test result based on expected behavior
	if [ "$total" -eq 0 ]; then
		echo "  RESULT: NO DATA"
		echo
		echo "  No certificates were found to compare."
		echo "  Ensure test certificates exist before running the test."
		return 2
	fi

	if [ "$EXPECT_PRESERVED" = true ]; then
		# Scenario 2: Expecting certificates to be PRESERVED
		if [ "$unchanged" -eq "$total" ] && [ "$changed" -eq 0 ]; then
			echo -e "  RESULT: ${GREEN}EXPECTED BEHAVIOR CONFIRMED${NC}"
			echo
			echo "  Certificates WERE preserved during IBU simulation."
			echo "  All certificates retained their original keys/certs."
			echo
			echo "  This confirms that using lca.openshift.io/apply-label:"
			echo "  - Properly labels resources for preservation"
			echo "  - Backup includes raw certificate/secret data"
			echo "  - Restore brings back original certificates"
			echo
			return 0
		elif [ "$unchanged" -gt 0 ]; then
			echo -e "  RESULT: ${YELLOW}PARTIAL - SOME CERTS PRESERVED${NC}"
			echo
			echo "  Some certificates were preserved, but not all."
			echo
			echo "  Preserved: $unchanged out of $total"
			echo "  Changed:   $changed out of $total"
			echo
			echo "  Check that all resources were properly labeled."
			echo
			return 1
		else
			echo -e "  RESULT: ${RED}UNEXPECTED - CERTS NOT PRESERVED${NC}"
			echo
			echo "  Certificates were NOT preserved despite labeling."
			echo "  All certificates received new keys/certs after restore."
			echo
			echo "  Possible causes:"
			echo "  - Resources not properly labeled before backup"
			echo "  - Backup did not include labeled resources"
			echo "  - cert-manager reconciled before state capture"
			echo
			return 1
		fi
	else
		# Scenario 1: Expecting certificates to be LOST
		if [ "$unchanged" -eq 0 ] && [ "$total" -gt 0 ]; then
			echo -e "  RESULT: ${GREEN}EXPECTED BEHAVIOR CONFIRMED${NC}"
			echo
			echo "  Certificates were NOT preserved during IBU simulation."
			echo "  All certificates received new keys/certs after restore."
			echo
			echo "  This confirms the known limitation:"
			echo "  - cert-manager issues NEW certificates after IBU"
			echo "  - Original certificate data is lost"
			echo "  - This is expected behavior as documented by Red Hat"
			echo
			return 0
		elif [ "$unchanged" -gt 0 ]; then
			echo -e "  RESULT: ${YELLOW}UNEXPECTED - SOME CERTS PRESERVED${NC}"
			echo
			echo "  Some certificates appear to have been preserved."
			echo "  This is unexpected for IBU simulation."
			echo
			echo "  Preserved: $unchanged out of $total"
			echo
			echo "  Possible causes:"
			echo "  - Backup included raw secret data"
			echo "  - Restore occurred before cert-manager reconciled"
			echo "  - Test timing issue"
			echo
			return 1
		fi
	fi
}

compare_metadata() {
	log_info "Comparing capture metadata..."

	local before_meta="$STATE_DIR/metadata-before.json"
	local after_meta="$STATE_DIR/metadata-after.json"

	if [ -f "$before_meta" ] && [ -f "$after_meta" ]; then
		local before_time
		before_time=$(jq -r '.captureTime' "$before_meta")
		local after_time
		after_time=$(jq -r '.captureTime' "$after_meta")

		echo "  Before capture: $before_time"
		echo "  After capture:  $after_time"
		echo
	fi
}

main() {
	print_validation_header
	check_prerequisites

	compare_metadata

	log_info "Comparing certificate checksums..."
	echo

	# Capture comparison results
	local results
	results=$(compare_checksums)

	# Parse results
	local changed
	local unchanged
	local missing
	local total

	IFS=',' read -r changed unchanged missing total <<<"$results"

	print_report "$changed" "$unchanged" "$missing" "$total"
}

main
