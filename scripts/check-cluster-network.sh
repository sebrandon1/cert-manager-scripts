#!/bin/bash

################################################################################
# Script: check-cluster-network.sh
# Description: Check OpenShift cluster network configuration (IPv4/IPv6/Dual-stack)
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# CYAN color not defined in common.sh, add locally
CYAN='\033[0;36m'

# Function to print detail messages with cyan color
log_detail() {
	echo -e "${CYAN}[DETAIL]${NC} $1"
}

# Function to get cluster version
get_cluster_version() {
	log_info "Checking OpenShift version..."
	local version
	version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "Unknown")
	echo "  OpenShift Version: $version"
	echo
}

# Function to check network type
check_network_type() {
	log_info "Checking network plugin type..."

	local network_type
	network_type=$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.networkType}' 2>/dev/null || echo "Unknown")
	echo "  Network Type: $network_type"

	case "$network_type" in
	"OVNKubernetes")
		log_detail "OVN-Kubernetes detected - Full IPv6 and dual-stack support available"
		;;
	"OpenShiftSDN")
		log_warn "OpenShift SDN detected - Limited IPv6 support (deprecated in 4.15+)"
		;;
	*)
		log_warn "Unknown network type: $network_type"
		;;
	esac
	echo
}

# Function to check IP families
check_ip_families() {
	local cluster_networks="$1"
	log_info "Checking cluster IP address families..."

	if [ -z "$cluster_networks" ]; then
		log_error "Unable to retrieve network configuration"
		return 1
	fi

	# Check cluster network CIDRs
	local cluster_cidrs
	cluster_cidrs=$(echo "$cluster_networks" | jq -r '.spec.clusterNetwork[]?.cidr' 2>/dev/null)
	local service_cidrs
	service_cidrs=$(echo "$cluster_networks" | jq -r '.spec.serviceNetwork[]?' 2>/dev/null)

	echo "  Cluster Networks:"
	local has_ipv4=false
	local has_ipv6=false

	while IFS= read -r cidr; do
		[[ -z "$cidr" ]] && continue
		echo "    - $cidr"
		if [[ "$cidr" =~ : ]]; then
			has_ipv6=true
		else
			has_ipv4=true
		fi
	done <<<"$cluster_cidrs"

	echo
	echo "  Service Networks:"
	while IFS= read -r cidr; do
		[[ -z "$cidr" ]] && continue
		echo "    - $cidr"
		if [[ "$cidr" =~ : ]]; then
			has_ipv6=true
		else
			has_ipv4=true
		fi
	done <<<"$service_cidrs"
	echo

	# Determine network stack
	if [ "$has_ipv4" = true ] && [ "$has_ipv6" = true ]; then
		log_info "Network Stack: ${GREEN}DUAL-STACK${NC} (IPv4 + IPv6)"
		echo "  ✓ IPv4 support: Enabled"
		echo "  ✓ IPv6 support: Enabled"
		echo "  ✓ Dual-stack: Enabled"
	elif [ "$has_ipv6" = true ]; then
		log_info "Network Stack: ${BLUE}IPv6 ONLY${NC}"
		echo "  ✗ IPv4 support: Disabled"
		echo "  ✓ IPv6 support: Enabled"
		echo "  ✗ Dual-stack: Not applicable (IPv6 only)"
	elif [ "$has_ipv4" = true ]; then
		log_info "Network Stack: ${CYAN}IPv4 ONLY${NC}"
		echo "  ✓ IPv4 support: Enabled"
		echo "  ✗ IPv6 support: Disabled"
		echo "  ✗ Dual-stack: Not applicable (IPv4 only)"
	else
		log_error "Unable to determine network stack"
	fi
	echo
}

# Function to check API server addresses
check_api_server() {
	log_info "Checking API Server configuration..."

	local api_url
	api_url=$(oc whoami --show-server 2>/dev/null)
	echo "  API Server URL: $api_url"

	# Extract hostname from URL
	local api_host
	api_host=$(echo "$api_url" | sed -E 's|https?://([^:/]+).*|\1|')

	if [ -n "$api_host" ]; then
		echo "  API Server Host: $api_host"

		# Try to resolve the hostname
		if command -v dig &>/dev/null; then
			echo
			echo "  DNS Resolution:"

			# Check for A record (IPv4)
			local ipv4_records
			ipv4_records=$(dig +short A "$api_host" 2>/dev/null | grep -v "^$" | head -3)
			if [ -n "$ipv4_records" ]; then
				echo "    IPv4 (A records):"
				echo "$ipv4_records" | while read -r ip; do
					echo "      - $ip"
				done
			fi

			# Check for AAAA record (IPv6)
			local ipv6_records
			ipv6_records=$(dig +short AAAA "$api_host" 2>/dev/null | grep -v "^$" | head -3)
			if [ -n "$ipv6_records" ]; then
				echo "    IPv6 (AAAA records):"
				echo "$ipv6_records" | while read -r ip; do
					echo "      - $ip"
				done
			fi

			if [ -z "$ipv4_records" ] && [ -z "$ipv6_records" ]; then
				log_warn "No DNS records found for $api_host"
			fi
		else
			log_detail "dig command not available - skipping DNS resolution check"
		fi
	fi
	echo
}

# Function to check node addresses
check_node_addresses() {
	log_info "Checking node IP addresses (first 3 nodes)..."

	local nodes
	nodes=$(oc get nodes -o json 2>/dev/null)

	if [ -z "$nodes" ]; then
		log_error "Unable to retrieve node information"
		return 1
	fi

	local node_count
	node_count=$(echo "$nodes" | jq -r '.items | length')
	local display_count=$((node_count < 3 ? node_count : 3))

	for i in $(seq 0 $((display_count - 1))); do
		local node_name
		node_name=$(echo "$nodes" | jq -r ".items[$i].metadata.name")
		local internal_ips
		internal_ips=$(echo "$nodes" | jq -r ".items[$i].status.addresses[] | select(.type==\"InternalIP\") | .address")

		echo "  Node: $node_name"
		while IFS= read -r ip; do
			[[ -z "$ip" ]] && continue
			if [[ "$ip" =~ : ]]; then
				echo "    - $ip (IPv6)"
			else
				echo "    - $ip (IPv4)"
			fi
		done <<<"$internal_ips"
	done

	if [ "$node_count" -gt 3 ]; then
		echo "  ... and $((node_count - 3)) more nodes"
	fi
	echo
}

# Function to check for common cert-manager services
check_cert_manager_compatibility() {
	log_info "Checking cert-manager compatibility..."

	# Check if cert-manager is installed
	if oc get namespace cert-manager &>/dev/null; then
		log_detail "cert-manager namespace found"

		# Check cert-manager pods
		local cm_pods
		cm_pods=$(oc get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
		if [ "$cm_pods" -gt 0 ]; then
			echo "  cert-manager components: $cm_pods pods running"
		fi
	else
		log_detail "cert-manager not yet installed"
	fi

	echo
	log_info "Compatibility notes:"
	echo "  ✓ cert-manager supports IPv4, IPv6, and dual-stack clusters"
	echo "  ✓ ACME challenges (HTTP-01, DNS-01) work with all network stacks"
	echo "  ✓ Pebble ACME server supports IPv4 and IPv6"
	echo
}

# Function to provide recommendations
provide_recommendations() {
	local cluster_networks="$1"
	print_header "Recommendations"

	local has_ipv4=false
	local has_ipv6=false

	local cluster_cidrs
	cluster_cidrs=$(echo "$cluster_networks" | jq -r '.spec.clusterNetwork[]?.cidr' 2>/dev/null)
	while IFS= read -r cidr; do
		[[ -z "$cidr" ]] && continue
		if [[ "$cidr" =~ : ]]; then
			has_ipv6=true
		else
			has_ipv4=true
		fi
	done <<<"$cluster_cidrs"

	if [ "$has_ipv4" = true ] && [ "$has_ipv6" = true ]; then
		echo "Your cluster supports DUAL-STACK networking:"
		echo "  • You can test both IPv4 and IPv6 scenarios"
		echo "  • Services can be created with either or both IP families"
		echo "  • Consider testing cert-manager with both protocols"
		echo "  • Pebble will be accessible via both IPv4 and IPv6"
	elif [ "$has_ipv6" = true ]; then
		echo "Your cluster is IPv6 ONLY:"
		echo "  • All services will use IPv6 addresses"
		echo "  • Ensure DNS records (AAAA) are configured for IPv6"
		echo "  • External services must support IPv6"
		echo "  • cert-manager will work with IPv6 ACME servers"
	else
		echo "Your cluster is IPv4 ONLY:"
		echo "  • This is the most common configuration"
		echo "  • All standard cert-manager features are supported"
		echo "  • Pebble will work normally with IPv4"
		echo "  • DNS records (A) should be configured for IPv4"
	fi
	echo

	echo "Next steps:"
	echo "  1. Install cert-manager: make install-cert-manager-operator"
	echo "  2. Install Pebble: make install-pebble"
	echo "  3. Test certificate issuance on your network stack"
	echo
}

# Function to export network info (for scripting)
export_network_info() {
	if [ "${EXPORT_FORMAT:-}" = "json" ]; then
		local cluster_networks
		cluster_networks=$(oc get network.config.openshift.io cluster -o json 2>/dev/null)
		echo "$cluster_networks" | jq '{
            clusterNetwork: .spec.clusterNetwork,
            serviceNetwork: .spec.serviceNetwork,
            networkType: .spec.networkType
        }'
	fi
}

# Main execution
main() {
	print_header "OpenShift Network Configuration Check"
	require_cmd oc
	require_cluster

	# Fetch network config once and cache it
	local cluster_networks
	cluster_networks=$(oc get network.config.openshift.io cluster -o json 2>/dev/null)

	get_cluster_version
	check_network_type
	check_ip_families "$cluster_networks"
	check_api_server
	check_node_addresses
	check_cert_manager_compatibility
	provide_recommendations "$cluster_networks"

	# Export if requested
	if [ "${EXPORT_FORMAT:-}" = "json" ]; then
		echo
		log_info "Network configuration (JSON):"
		export_network_info
	fi
}

# Run main function
main
