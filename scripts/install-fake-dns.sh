#!/bin/bash

################################################################################
# Script: install-fake-dns.sh
# Description: Install fake DNS API server for air-gapped DNS-01 testing
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/fake-dns-api"

export FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"

install_fake_dns() {
	log_info "Installing fake DNS API server..."

	apply_yaml_template "$YAML_DIR/namespace.yaml" "Namespace"
	apply_yaml_template "$YAML_DIR/serviceaccount.yaml" "ServiceAccount"

	log_info "Granting anyuid SCC to fake-dns-api ServiceAccount..."
	oc adm policy add-scc-to-user anyuid -z fake-dns-api -n "$FAKEDNS_NAMESPACE"

	apply_yaml_template "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml_template "$YAML_DIR/service.yaml" "Service"

	log_info "Resources applied. Waiting for fake-dns-api to be ready..."
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

	local fake_dns_ip=$(oc get service fake-dns-api -n "$FAKEDNS_NAMESPACE" -o jsonpath='{.spec.clusterIP}')

	if [ -z "$fake_dns_ip" ]; then
		log_error "Could not get fake-dns service ClusterIP"
		exit 1
	fi

	log_info "Fake DNS server IP: $fake_dns_ip"

	if ! oc get configmap dns-default -n openshift-dns &>/dev/null; then
		log_warn "CoreDNS configmap not found, skipping CoreDNS configuration"
		log_warn "You may need to manually configure DNS forwarding for example.com"
		return
	fi

	local corefile=$(oc get configmap dns-default -n openshift-dns -o jsonpath='{.data.Corefile}')

	if echo "$corefile" | grep -q "example.com:53"; then
		log_info "CoreDNS already configured for example.com"
	else
		log_info "Adding example.com zone to CoreDNS..."

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
	log_info "This fake DNS server accepts RFC2136 update requests and returns success"
	log_info "without actually updating DNS. Perfect for air-gapped DNS-01 testing!"
	echo
	log_info "CoreDNS has been configured to forward example.com queries to fake DNS."
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
	print_header "Install Fake DNS API (Air-gapped)"

	require_cmd oc envsubst
	require_cluster

	install_fake_dns
	wait_for_resource "deployment/fake-dns-api" "$FAKEDNS_NAMESPACE" "600s"
	verify_installation
	configure_coredns
	display_next_steps
}

main
