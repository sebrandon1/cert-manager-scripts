#!/bin/bash

################################################################################
# Script: check-workload-partitioning.sh
# Description: Verify that cert-manager pods are NOT annotated for workload partitioning
#
# Workload partitioning is used to isolate management workloads in SNO/compact clusters.
# cert-manager pods should NOT be annotated with workload partitioning annotations
# to ensure they run on all nodes and are not restricted to specific CPU sets.
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

# Print header
print_header() {
	echo
	echo "========================================"
	echo "  Workload Partitioning Check"
	echo "========================================"
	echo
}

# Check prerequisites
check_prerequisites() {
	if ! command -v oc &>/dev/null; then
		log_error "oc command not found. Please install OpenShift CLI."
		exit 1
	fi

	if ! oc whoami &>/dev/null; then
		log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
		exit 1
	fi

	# Check if jq is available (optional but helpful)
	if ! command -v jq &>/dev/null; then
		log_warn "jq not found - output will be less detailed"
	fi
}

# Check if cert-manager is installed
check_cert_manager_exists() {
	if ! oc get namespace cert-manager &>/dev/null; then
		log_error "cert-manager namespace not found"
		log_info "cert-manager does not appear to be installed"
		exit 1
	fi
}

# Check for workload partitioning annotations
check_workload_partitioning() {
	local namespace=$1
	local has_issues=0

	log_info "Checking cert-manager pods in namespace: $namespace"
	echo

	# Get all pods in the cert-manager namespace
	local pods=$(oc get pods -n "$namespace" -o json 2>/dev/null)

	if [ -z "$pods" ] || [ "$(echo "$pods" | jq -r '.items | length')" -eq 0 ]; then
		log_warn "No pods found in namespace $namespace"
		return 0
	fi

	# Check each pod for workload partitioning annotations
	local pod_count=$(echo "$pods" | jq -r '.items | length')
	log_info "Found $pod_count pod(s) to check"
	echo

	for i in $(seq 0 $((pod_count - 1))); do
		local pod_name=$(echo "$pods" | jq -r ".items[$i].metadata.name")
		local annotations=$(echo "$pods" | jq -r ".items[$i].metadata.annotations // {}")

		log_detail "Checking pod: $pod_name"

		# Check for the workload partitioning annotation
		local wp_annotation=$(echo "$annotations" | jq -r '."target.workload.openshift.io/management" // empty')

		if [ -n "$wp_annotation" ]; then
			log_error "  ❌ Pod has workload partitioning annotation!"
			log_error "     Annotation: target.workload.openshift.io/management=$wp_annotation"
			has_issues=1
			echo
		else
			log_info "  ✅ Pod does NOT have workload partitioning annotation"
			echo
		fi

		# Also check for other workload-related annotations
		local other_wp_annotations=$(echo "$annotations" | jq -r 'to_entries | map(select(.key | contains("workload"))) | .[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")

		if [ -n "$other_wp_annotations" ]; then
			log_warn "  ⚠️  Other workload-related annotations found:"
			echo "$other_wp_annotations" | while read -r line; do
				if [ -n "$line" ]; then
					log_warn "     $line"
				fi
			done
			echo
		fi
	done

	return $has_issues
}

# Check cert-manager deployment/daemonset configurations
check_deployment_configs() {
	local namespace=$1
	local has_issues=0

	log_info "Checking cert-manager deployment configurations..."
	echo

	# Check deployments
	local deployments=$(oc get deployments -n "$namespace" -o json 2>/dev/null)
	if [ -n "$deployments" ]; then
		local deploy_count=$(echo "$deployments" | jq -r '.items | length')

		for i in $(seq 0 $((deploy_count - 1))); do
			local deploy_name=$(echo "$deployments" | jq -r ".items[$i].metadata.name")
			local pod_annotations=$(echo "$deployments" | jq -r ".items[$i].spec.template.metadata.annotations // {}")

			log_detail "Checking deployment: $deploy_name"

			local wp_annotation=$(echo "$pod_annotations" | jq -r '."target.workload.openshift.io/management" // empty')

			if [ -n "$wp_annotation" ]; then
				log_error "  ❌ Deployment template has workload partitioning annotation!"
				log_error "     This will apply to all pods created by this deployment"
				has_issues=1
			else
				log_info "  ✅ Deployment template does NOT have workload partitioning annotation"
			fi
			echo
		done
	fi

	return $has_issues
}

# Provide recommendations
provide_recommendations() {
	local has_issues=$1

	echo
	echo "========================================"
	echo "  Summary"
	echo "========================================"
	echo

	if [ $has_issues -eq 0 ]; then
		log_info "✅ All checks passed!"
		echo
		log_info "cert-manager pods are correctly configured without workload partitioning annotations."
		echo
		log_info "This ensures cert-manager can run on all nodes and is not restricted to specific CPU sets."
	else
		log_error "❌ Issues found!"
		echo
		log_error "cert-manager pods have workload partitioning annotations."
		echo
		log_info "Workload partitioning should NOT be used for cert-manager because:"
		echo "  • cert-manager needs to run on all node types"
		echo "  • Restricting to management CPU sets can cause performance issues"
		echo "  • cert-manager webhook needs to be accessible cluster-wide"
		echo
		log_info "To fix this issue:"
		echo "  1. Check the CertManager custom resource for annotations"
		echo "  2. Remove any workload partitioning annotations from:"
		echo "     - CertManager CR"
		echo "     - cert-manager deployments"
		echo "     - cert-manager namespace"
		echo "  3. Restart cert-manager pods to pick up the changes"
		echo
		log_info "For more information, see:"
		echo "  https://docs.openshift.com/container-platform/latest/scalability_and_performance/ztp_far_edge/ztp-reference-cluster-configuration-for-vdu.html#ztp-du-cluster-config-workload-partitioning_sno-configure-for-vdu"
	fi
	echo
}

# Main execution
main() {
	print_header
	check_prerequisites
	check_cert_manager_exists

	local namespace="cert-manager"
	local exit_code=0

	# Check running pods
	if ! check_workload_partitioning "$namespace"; then
		exit_code=1
	fi

	# Check deployment configurations
	if ! check_deployment_configs "$namespace"; then
		exit_code=1
	fi

	# Provide recommendations
	provide_recommendations $exit_code

	exit $exit_code
}

# Run main function
main
