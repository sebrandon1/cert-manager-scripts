#!/bin/bash

################################################################################
# Script: check-network-stack.sh
# Description: Detect and verify IPv4/IPv6/dual-stack configuration
# Usage: ./scripts/troubleshooting/check-network-stack.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Function to detect cluster network configuration
detect_cluster_network() {
	log_info "Detecting cluster network configuration..."
	echo

	# Get network configuration from cluster
	local cluster_network=$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.clusterNetwork[*].cidr}' 2>/dev/null || echo "")
	local service_network=$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.serviceNetwork[*]}' 2>/dev/null || echo "")

	log_debug "Cluster Networks: ${cluster_network:-Not found}"
	log_debug "Service Networks: ${service_network:-Not found}"

	# Detect stack type
	local has_ipv4=false
	local has_ipv6=false

	# Check cluster network
	if echo "$cluster_network" | grep -q "\."; then
		has_ipv4=true
	fi
	if echo "$cluster_network" | grep -q ":"; then
		has_ipv6=true
	fi

	# Check service network
	if echo "$service_network" | grep -q "\."; then
		has_ipv4=true
	fi
	if echo "$service_network" | grep -q ":"; then
		has_ipv6=true
	fi

	# Determine stack type
	if $has_ipv4 && $has_ipv6; then
		echo "dual-stack"
	elif $has_ipv6; then
		echo "ipv6"
	elif $has_ipv4; then
		echo "ipv4"
	else
		echo "unknown"
	fi
}

# Function to check node addresses
check_node_addresses() {
	log_info "Checking node IP addresses..."
	echo

	local nodes=$(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

	local has_ipv4_nodes=false
	local has_ipv6_nodes=false

	while IFS=$'\t' read -r node_name node_ip; do
		log_debug "Node: $node_name"
		log_debug "  IP: $node_ip"

		if echo "$node_ip" | grep -q "\."; then
			has_ipv4_nodes=true
		fi
		if echo "$node_ip" | grep -q ":"; then
			has_ipv6_nodes=true
		fi
	done <<<"$nodes"

	echo
	if $has_ipv4_nodes && $has_ipv6_nodes; then
		log_info "✅ Nodes have dual-stack addresses"
		return 0
	elif $has_ipv6_nodes; then
		log_info "✅ Nodes have IPv6 addresses"
		return 0
	elif $has_ipv4_nodes; then
		log_info "✅ Nodes have IPv4 addresses"
		return 0
	else
		log_warn "⚠️  Could not detect node IP addresses"
		return 1
	fi
}

# Function to check cert-manager pod addresses
check_certmanager_pods() {
	log_info "Checking cert-manager pod IP addresses..."
	echo

	local pods=$(oc get pods -n cert-manager -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}' 2>/dev/null || echo "")

	if [ -z "$pods" ]; then
		log_warn "⚠️  cert-manager pods not found or not running"
		return 1
	fi

	local has_ipv4_pods=false
	local has_ipv6_pods=false

	while IFS=$'\t' read -r pod_name pod_ip; do
		if [ -n "$pod_ip" ]; then
			log_debug "Pod: $pod_name"
			log_debug "  IP: $pod_ip"

			if echo "$pod_ip" | grep -q "\."; then
				has_ipv4_pods=true
			fi
			if echo "$pod_ip" | grep -q ":"; then
				has_ipv6_pods=true
			fi
		fi
	done <<<"$pods"

	echo
	if $has_ipv4_pods && $has_ipv6_pods; then
		log_info "✅ cert-manager pods have dual-stack addresses"
		return 0
	elif $has_ipv6_pods; then
		log_info "✅ cert-manager pods have IPv6 addresses"
		return 0
	elif $has_ipv4_pods; then
		log_info "✅ cert-manager pods have IPv4 addresses"
		return 0
	else
		log_warn "⚠️  Could not detect cert-manager pod IP addresses"
		return 1
	fi
}

# Function to test cert-manager webhook connectivity
check_webhook_connectivity() {
	log_info "Checking cert-manager webhook service..."
	echo

	local webhook_cluster_ip=$(oc get service cert-manager-webhook -n cert-manager -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
	local webhook_cluster_ips=$(oc get service cert-manager-webhook -n cert-manager -o jsonpath='{.spec.clusterIPs[*]}' 2>/dev/null || echo "")

	if [ -n "$webhook_cluster_ip" ]; then
		log_debug "Webhook ClusterIP: $webhook_cluster_ip"
	fi

	if [ -n "$webhook_cluster_ips" ]; then
		log_debug "Webhook ClusterIPs: $webhook_cluster_ips"

		if echo "$webhook_cluster_ips" | grep -q " "; then
			log_info "✅ Webhook service has multiple ClusterIPs (dual-stack capable)"
		else
			log_info "✅ Webhook service has single ClusterIP"
		fi
	else
		log_warn "⚠️  Could not find webhook service"
		return 1
	fi
}

# Main execution
main() {
	print_header "Network Stack Detection"

	require_cmd oc
	require_cluster

	# Detect stack type
	local stack_type=$(detect_cluster_network)

	echo
	echo "========================================"
	echo "  Network Stack Summary"
	echo "========================================"
	echo

	case "$stack_type" in
	"dual-stack")
		log_info "🌐 Cluster Network Stack: DUAL-STACK (IPv4 + IPv6)"
		echo
		log_info "This cluster supports both IPv4 and IPv6 networking."
		log_info "cert-manager should be able to handle both address families."
		;;
	"ipv6")
		log_info "🌐 Cluster Network Stack: IPv6 ONLY"
		echo
		log_info "This cluster uses IPv6 networking exclusively."
		log_info "cert-manager must support IPv6 for ACME challenges."
		;;
	"ipv4")
		log_info "🌐 Cluster Network Stack: IPv4 ONLY"
		echo
		log_info "This cluster uses IPv4 networking (standard configuration)."
		log_info "cert-manager will work with standard IPv4 ACME challenges."
		;;
	*)
		log_warn "⚠️  Could not determine cluster network stack type"
		echo
		log_warn "This may indicate a cluster configuration issue."
		;;
	esac

	echo
	echo "========================================"
	echo "  Detailed Network Information"
	echo "========================================"
	echo

	check_node_addresses
	echo
	check_certmanager_pods
	echo
	check_webhook_connectivity

	echo
	echo "========================================"
	echo "  Recommendations"
	echo "========================================"
	echo

	if [ "$stack_type" = "ipv6" ] || [ "$stack_type" = "dual-stack" ]; then
		log_info "IPv6 Considerations for cert-manager:"
		echo
		echo "  • Ensure ACME server supports IPv6"
		echo "  • HTTP-01 challenges require IPv6 ingress route"
		echo "  • DNS-01 challenges work regardless of IP version"
		echo "  • Webhook must be accessible via IPv6"
		echo
		log_info "Testing IPv6 functionality:"
		echo
		echo "  1. Create a test certificate with DNS-01 (safest for IPv6)"
		echo "  2. Verify ACME challenge completes successfully"
		echo "  3. Check cert-manager logs for IPv6-related errors"
		echo
	fi

	if [ "$stack_type" = "ipv4" ]; then
		log_info "✅ Standard IPv4 configuration detected"
		echo
		log_info "No special IPv6 considerations needed."
		log_info "All cert-manager features should work normally."
	fi

	echo
}

main "$@"
