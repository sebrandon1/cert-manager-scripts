#!/bin/bash

################################################################################
# Script: preflight-dns01.sh
# Description: Verify fake-dns and CoreDNS delegation before issuing a DNS-01
#              certificate. Exits non-zero when the cluster is not ready.
# Used by: Makefile quick-dns-test and test-dns01 (after install-fake-dns)
#
# install-fake-dns waits for the Deployment but never checks that CoreDNS
# actually answers queries for the delegated zone, which is the dependency the
# ACME DNS-01 solver needs.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0
load_env

FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"
PREFLIGHT_DNS_NAME="${PREFLIGHT_DNS_NAME:-example.com}"

fail() {
	log_error "$1"
	if [[ -n "${2:-}" ]]; then
		log_hint "$2"
	fi
	log_error "DNS-01 preflight FAILED - not creating DNS-01 issuer/certificate"
	exit 1
}

# Raw UDP SOA query from inside the fake-dns pod. The image ships python3 but
# no bind-utils, so nslookup/host are unavailable. SOA is what cert-manager's
# RFC2136 path resolves; the fake DNS answers SOA but returns NODATA for A.
probe_soa() {
	local dns_ip="$1" pod="$2"
	kube_timed exec -i "$pod" -n "$FAKEDNS_NAMESPACE" -- python3 - "$dns_ip" "$PREFLIGHT_DNS_NAME" <<'PY'
import socket
import struct
import sys

dns_ip = sys.argv[1]
name = sys.argv[2]


def encode_name(value):
    out = b""
    for label in value.split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


# id, flags (standard query, recursion desired), qdcount=1
query = struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
query += encode_name(name)
query += struct.pack(">HH", 6, 1)  # QTYPE=SOA, QCLASS=IN

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(5)
try:
    sock.sendto(query, (dns_ip, 53))
    data, _ = sock.recvfrom(4096)
except Exception as exc:  # noqa: BLE001 - any failure means "not ready yet"
    print("SOA query for %s to %s:53 failed: %s" % (name, dns_ip, exc))
    sys.exit(1)

if len(data) < 12:
    print("SOA reply too short (%d bytes)" % len(data))
    sys.exit(1)

flags, _qdcount, ancount, _nscount, _arcount = struct.unpack(">HHHHH", data[2:12])
qr = (flags >> 15) & 1
rcode = flags & 0xF
print("SOA reply: qr=%d rcode=%d ancount=%d" % (qr, rcode, ancount))
sys.exit(0 if qr == 1 and rcode == 0 and ancount >= 1 else 1)
PY
}

check_node_pressure() {
	local pressured
	pressured=$(node_pressure_conditions | awk -F'\t' '$2 ~ /True/ || $3 ~ /True/')
	if [[ -n "$pressured" ]]; then
		log_error "Nodes under resource pressure:"
		echo "$pressured"
		fail "Node memory/disk pressure prevents reliable DNS-01 validation" \
			"Inspect node conditions: $KUBE_CLI describe node"
	fi
	log_info "✅ No node memory/disk pressure"
}

check_fake_dns_deployment() {
	if ! deployment_has_available_replica fake-dns-api "$FAKEDNS_NAMESPACE"; then
		fail "fake-dns-api has no available replica" \
			"Check: $KUBE_CLI get pods -n $FAKEDNS_NAMESPACE -o wide"
	fi
	log_info "✅ fake-dns-api has an available replica"
}

check_fake_dns_pods() {
	local stuck
	stuck=$(unhealthy_pods "$FAKEDNS_NAMESPACE")
	if [[ -z "$stuck" ]]; then
		log_info "✅ No stuck fake-dns pods"
		return 0
	fi

	if deployment_has_available_replica fake-dns-api "$FAKEDNS_NAMESPACE"; then
		log_warn "Stuck fake-dns pods present, but the deployment has a healthy replica:"
		echo "$stuck"
		return 0
	fi

	log_error "Unhealthy fake-dns pods:"
	echo "$stuck"
	fail "fake-dns namespace contains stuck pods and no healthy replica" \
		"Run: make clean-fake-dns && make install-fake-dns"
}

check_delegation() {
	local fake_dns_ip
	fake_dns_ip=$(kube_timed get service fake-dns-api -n "$FAKEDNS_NAMESPACE" \
		-o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
	if [[ -z "$fake_dns_ip" ]]; then
		fail "Could not read fake-dns-api service ClusterIP" \
			"Check: $KUBE_CLI get service fake-dns-api -n $FAKEDNS_NAMESPACE"
	fi

	if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
		if ! kube_timed get dns.operator.openshift.io/default \
			-o jsonpath='{.spec.servers[?(@.name=="fake-dns-example")].zones}' 2>/dev/null | grep -qF "$PREFLIGHT_DNS_NAME"; then
			fail "DNS operator CR has no fake-dns-example server for $PREFLIGHT_DNS_NAME" \
				"Re-run: make install-fake-dns"
		fi
		if ! kube_timed get configmap dns-default -n openshift-dns \
			-o jsonpath='{.data.Corefile}' 2>/dev/null | grep -qF "$fake_dns_ip"; then
			fail "dns-default Corefile does not reference $fake_dns_ip yet" \
				"CoreDNS may still be reloading; re-run the preflight"
		fi
	else
		if ! kube_timed get configmap coredns -n kube-system \
			-o jsonpath='{.data.Corefile}' 2>/dev/null | grep -qF "$fake_dns_ip"; then
			fail "coredns Corefile does not reference $fake_dns_ip yet" \
				"Re-run: make install-fake-dns"
		fi
	fi
	log_success "CoreDNS delegation to fake-dns ($fake_dns_ip) is configured"
}

check_dns_resolution() {
	local dns_service_ip pod

	if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
		dns_service_ip=$(kube_timed get service dns-default -n openshift-dns \
			-o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
	else
		dns_service_ip=$(kube_timed get service kube-dns -n kube-system \
			-o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
	fi
	if [[ -z "$dns_service_ip" ]]; then
		fail "Could not determine cluster DNS service ClusterIP" \
			"Check the cluster DNS service exists and is healthy"
	fi

	pod=$(kube_timed get pods -n "$FAKEDNS_NAMESPACE" -l app=fake-dns-api \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
	if [[ -z "$pod" ]]; then
		fail "Could not find a fake-dns-api pod to run the DNS probe from" \
			"Check: $KUBE_CLI get pods -n $FAKEDNS_NAMESPACE"
	fi

	log_info "Probing $PREFLIGHT_DNS_NAME SOA via CoreDNS ($dns_service_ip) from pod/$pod..."
	local attempt=1
	while true; do
		if probe_soa "$dns_service_ip" "$pod"; then
			log_success "CoreDNS resolves $PREFLIGHT_DNS_NAME via fake-dns (SOA answer received)"
			return 0
		fi
		if [[ $attempt -ge 6 ]]; then
			log_error "fake-dns service ClusterIP: $(kube_timed get service fake-dns-api -n "$FAKEDNS_NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo unknown)"
			fail "CoreDNS did not return a SOA answer for $PREFLIGHT_DNS_NAME after 30s" \
				"Check CoreDNS config and fake-dns logs: $KUBE_CLI logs -n $FAKEDNS_NAMESPACE -l app=fake-dns-api"
		fi
		log_info "  CoreDNS not answering yet ($attempt/6); retrying in 5s..."
		sleep 5
		attempt=$((attempt + 1))
	done
}

print_header "DNS-01 Preflight"

require_cmd "$KUBE_CLI"
require_cluster

if ! retry 3 5 kube_timed get namespace default >/dev/null 2>&1; then
	fail "Cluster API is not responding" "Check cluster health: ./scripts/workflows/verify-cluster-access.sh"
fi

check_node_pressure
check_fake_dns_deployment
check_fake_dns_pods
check_delegation
check_dns_resolution

print_header "DNS-01 Preflight Passed"
log_success "fake-dns, CoreDNS delegation and DNS resolution are healthy"
echo
