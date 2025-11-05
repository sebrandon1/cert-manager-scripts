#!/bin/bash

################################################################################
# Script: install-fake-dns.sh
# Description: Install fake DNS API server for air-gapped DNS-01 testing
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/../yaml/fake-dns-api"

# Configuration
export FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_note() { echo -e "${BLUE}[NOTE]${NC} $1"; }

print_header() {
	echo
	echo "========================================"
	echo "  Install Fake DNS API (Air-gapped)"
	echo "========================================"
	echo
}

check_prerequisites() {
	log_info "Checking prerequisites..."

	if ! command -v oc &>/dev/null; then
		log_error "oc command not found"
		exit 1
	fi

	if ! command -v envsubst &>/dev/null; then
		log_error "envsubst command not found"
		exit 1
	fi

	if ! oc whoami &>/dev/null; then
		log_error "Not logged into OpenShift"
		exit 1
	fi

	log_info "Prerequisites check passed"
}

apply_yaml() {
	local yaml_file=$1
	local resource_type=$2

	if [ ! -f "$yaml_file" ]; then
		log_error "YAML file not found: $yaml_file"
		exit 1
	fi

	log_info "Applying $resource_type from $(basename "$yaml_file")..."
	envsubst <"$yaml_file" | oc apply -f -
}

install_fake_dns() {
	log_info "Installing fake DNS API server..."

	apply_yaml "$YAML_DIR/namespace.yaml" "Namespace"
	apply_yaml "$YAML_DIR/serviceaccount.yaml" "ServiceAccount"

	# Grant anyuid SCC to allow binding to port 53
	log_info "Granting anyuid SCC to fake-dns-api ServiceAccount..."
	oc adm policy add-scc-to-user anyuid -z fake-dns-api -n "$FAKEDNS_NAMESPACE"

	apply_yaml "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml "$YAML_DIR/service.yaml" "Service"

	log_info "Resources applied. Waiting for fake-dns-api to be ready..."
}

wait_for_fake_dns() {
	log_info "Waiting for fake-dns-api deployment..."

	local max_attempts=120 # 10 minutes total
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		if oc get deployment fake-dns-api -n "$FAKEDNS_NAMESPACE" &>/dev/null; then
			local ready=$(oc get deployment fake-dns-api -n "$FAKEDNS_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
			if [ "$ready" != "0" ]; then
				log_info "fake-dns-api is ready!"
				break
			fi

			# Show pod status periodically for better feedback
			if [ $((attempt % 12)) -eq 0 ] && [ $attempt -gt 0 ]; then
				echo
				log_info "Still waiting... Current pod status:"
				oc get pods -n "$FAKEDNS_NAMESPACE" --no-headers 2>/dev/null || true
			fi
		fi

		attempt=$((attempt + 1))
		if [ $((attempt % 6)) -eq 0 ]; then
			echo -n " [${attempt}/${max_attempts}]"
		else
			echo -n "."
		fi
		sleep 5
	done
	echo

	if [ $attempt -eq $max_attempts ]; then
		log_error "Timeout waiting for fake-dns-api"
		exit 1
	fi
}

verify_installation() {
	log_info "Verifying fake-dns-api installation..."

	oc get pods -n "$FAKEDNS_NAMESPACE"
	echo
	oc get service fake-dns-api -n "$FAKEDNS_NAMESPACE"
	echo
}

configure_coredns() {
	log_info "Configuring CoreDNS to delegate example.com to fake DNS server..."

	# Get the fake-dns ClusterIP
	local fake_dns_ip=$(oc get service fake-dns-api -n "$FAKEDNS_NAMESPACE" -o jsonpath='{.spec.clusterIP}')

	if [ -z "$fake_dns_ip" ]; then
		log_error "Could not get fake-dns service ClusterIP"
		exit 1
	fi

	log_info "Fake DNS server IP: $fake_dns_ip"

	# Check if CoreDNS configmap exists
	if ! oc get configmap dns-default -n openshift-dns &>/dev/null; then
		log_warn "CoreDNS configmap not found, skipping CoreDNS configuration"
		log_warn "You may need to manually configure DNS forwarding for example.com"
		return
	fi

	# Update CoreDNS to forward example.com to our fake DNS
	local corefile=$(oc get configmap dns-default -n openshift-dns -o jsonpath='{.data.Corefile}')

	if echo "$corefile" | grep -q "example.com:53"; then
		log_info "CoreDNS already configured for example.com"
	else
		log_info "Adding example.com zone to CoreDNS..."

		# Add example.com zone configuration
		cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: dns-default
  namespace: openshift-dns
data:
  Corefile: |
    example.com:53 {
        forward . ${fake_dns_ip}
    }
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            upstream
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            policy sequential
        }
        cache 30
        reload
    }
EOF

		log_info "CoreDNS configured. Waiting for DNS pods to restart..."
		sleep 10
	fi
}

display_next_steps() {
	local dns_server="fake-dns-api.${FAKEDNS_NAMESPACE}.svc.cluster.local:53"

	echo
	log_info "========================================"
	log_info "  Fake DNS API Installation Complete!"
	log_info "========================================"
	echo
	log_note "This fake DNS server accepts RFC2136 update requests and returns success"
	log_note "without actually updating DNS. Perfect for air-gapped DNS-01 testing!"
	echo
	log_note "CoreDNS has been configured to forward example.com queries to fake DNS."
	echo
	echo "Next steps:"
	echo
	echo "1. Update Pebble to use fake DNS server:"
	echo "   oc delete namespace pebble"
	echo "   DNS_SERVER=${dns_server} PEBBLE_ALWAYS_VALID=1 ./install-pebble.sh"
	echo
	echo "2. Create DNS-01 ClusterIssuer pointing to fake DNS:"
	echo "   DNS_SERVER=${dns_server} ./create-dns01-issuer.sh"
	echo
	echo "3. Create wildcard certificate:"
	echo "   oc apply -f - <<EOF"
	echo "   apiVersion: cert-manager.io/v1"
	echo "   kind: Certificate"
	echo "   metadata:"
	echo "     name: wildcard-test"
	echo "     namespace: default"
	echo "   spec:"
	echo "     secretName: wildcard-test-tls"
	echo "     issuerRef:"
	echo "       name: pebble-dns01-issuer"
	echo "       kind: ClusterIssuer"
	echo "     dnsNames:"
	echo "     - '*.example.com'"
	echo "     - 'example.com'"
	echo "   EOF"
	echo
	echo "4. Watch certificate status:"
	echo "   watch oc get certificate -n default"
	echo
	log_info "DNS server: ${dns_server}"
	echo
}

main() {
	print_header
	check_prerequisites
	install_fake_dns
	wait_for_fake_dns
	verify_installation
	configure_coredns
	display_next_steps
}

main
