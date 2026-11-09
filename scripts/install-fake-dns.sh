#!/bin/bash

################################################################################
# Script: install-fake-dns.sh
# Description: Install fake DNS API server for air-gapped DNS-01 testing
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
check_help "$@" && exit 0
load_env

# Component namespaces (match the installers' defaults)
PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"

setup_cleanup

YAML_DIR="${SCRIPT_DIR}/../yaml/fake-dns-api"

export FAKEDNS_NAMESPACE="${FAKEDNS_NAMESPACE:-fake-dns}"
export UBI9_PYTHON_VERSION="${UBI9_PYTHON_VERSION:-9.8}"

# The pre-install DNS configuration is stored here so make clean can restore it.
# Use a namespace that make clean does not delete (clean-fake-dns deletes the
# fake-dns namespace).
BACKUP_NAMESPACE="${CERT_NAMESPACE:-default}"
BACKUP_CONFIGMAP="fake-dns-backup"

if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
	DNS_NAMESPACE="openshift-dns"
	DNS_CONFIGMAP="dns-default"
	DNS_ROLLOUT_TARGET="daemonset/dns-default"
else
	DNS_NAMESPACE="kube-system"
	DNS_CONFIGMAP="coredns"
	DNS_ROLLOUT_TARGET="deployment/coredns"
fi

install_fake_dns() {
	log_info "Installing fake DNS API server..."

	apply_yaml_template "$YAML_DIR/namespace.yaml" "Namespace"
	register_rollback "$KUBE_CLI" delete namespace "$FAKEDNS_NAMESPACE" --ignore-not-found=true --wait=false
	apply_yaml_template "$YAML_DIR/serviceaccount.yaml" "ServiceAccount"
	apply_yaml_template "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml_template "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml_template "$YAML_DIR/service.yaml" "Service"

	log_info "Resources applied. Waiting for fake-dns-api to be ready..."
}

verify_installation() {
	log_info "Verifying fake-dns-api installation..."

	"$KUBE_CLI" get pods -n "$FAKEDNS_NAMESPACE"
	echo
	"$KUBE_CLI" get service fake-dns-api -n "$FAKEDNS_NAMESPACE"
	echo
}

configure_coredns() {
	log_info "Configuring CoreDNS to delegate example.com to fake DNS server..."

	local fake_dns_ip
	fake_dns_ip=$("$KUBE_CLI" get service fake-dns-api -n "$FAKEDNS_NAMESPACE" -o jsonpath='{.spec.clusterIP}')

	if [ -z "$fake_dns_ip" ]; then
		log_error "Could not get fake-dns service ClusterIP"
		log_hint "Check fake-dns deployment: make status"
		exit 1
	fi

	log_info "Fake DNS server IP: $fake_dns_ip"

	if [[ "${CLUSTER_TYPE:-}" == "openshift" ]]; then
		configure_coredns_openshift "$fake_dns_ip"
	else
		configure_coredns_kubernetes "$fake_dns_ip"
	fi
}

backup_exists() {
	"$KUBE_CLI" get configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" &>/dev/null
}

save_openshift_dns_backup() {
	if backup_exists; then
		return 0
	fi

	local servers
	servers=$("$KUBE_CLI" get dns.operator.openshift.io/default -o json 2>/dev/null | jq -c '.spec.servers // null' || true)
	[[ -z "$servers" ]] && servers="null"

	log_info "Saving the current DNS operator configuration to $BACKUP_NAMESPACE/$BACKUP_CONFIGMAP"
	"$KUBE_CLI" create configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" \
		--from-literal=mode=openshift --from-literal="servers.json=$servers" \
		--dry-run=client -o yaml | "$KUBE_CLI" apply -f - >/dev/null
}

save_kubernetes_dns_backup() {
	if backup_exists; then
		return 0
	fi

	local corefile="$1"
	log_info "Saving the current CoreDNS Corefile to $BACKUP_NAMESPACE/$BACKUP_CONFIGMAP"
	"$KUBE_CLI" create configmap "$BACKUP_CONFIGMAP" -n "$BACKUP_NAMESPACE" \
		--from-literal=mode=kubernetes --from-literal="Corefile=$corefile" \
		--dry-run=client -o yaml | "$KUBE_CLI" apply -f - >/dev/null
}

configure_coredns_openshift() {
	local fake_dns_ip="$1"

	# Check if already configured via DNS operator CR
	if "$KUBE_CLI" get dns.operator.openshift.io/default \
		-o jsonpath='{.spec.servers[*].name}' 2>/dev/null | grep -q "fake-dns-example"; then
		log_info "DNS operator already configured for example.com"
		return
	fi

	register_rollback make -C "$SCRIPT_DIR/.." clean-dns-config
	save_openshift_dns_backup

	local fake_entry
	fake_entry=$(printf '{"name":"fake-dns-example","zones":["example.com"],"forwardPlugin":{"upstreams":["%s:53"]}}' "$fake_dns_ip")
	local servers
	servers=$("$KUBE_CLI" get dns.operator.openshift.io/default -o json 2>/dev/null | jq -c '.spec.servers // null' || true)

	log_info "Patching DNS operator CR to forward example.com to fake DNS (existing servers kept)..."
	if [[ -z "$servers" || "$servers" == "null" ]]; then
		"$KUBE_CLI" patch dns.operator.openshift.io/default --type=merge \
			-p "{\"spec\":{\"servers\":[${fake_entry}]}}"
	else
		"$KUBE_CLI" patch dns.operator.openshift.io/default --type=json \
			-p "[{\"op\":\"add\",\"path\":\"/spec/servers/-\",\"value\":${fake_entry}}]"
	fi

	log_info "Waiting for DNS operator to update CoreDNS ConfigMap..."
	local attempt=0
	while [ "$attempt" -lt 18 ]; do
		if "$KUBE_CLI" get configmap "$DNS_CONFIGMAP" -n "$DNS_NAMESPACE" \
			-o jsonpath='{.data.Corefile}' 2>/dev/null | grep -q "${fake_dns_ip}"; then
			log_success "CoreDNS ConfigMap updated by DNS operator"
			log_info "Waiting 30s for CoreDNS reload plugin to apply changes..."
			sleep 30
			return 0
		fi
		attempt=$((attempt + 1))
		log_info "Waiting for DNS operator to propagate config ($attempt/18)..."
		sleep 10
	done
	log_warn "DNS operator may not have updated CoreDNS yet after 180s"
}

configure_coredns_kubernetes() {
	local fake_dns_ip="$1"

	if ! "$KUBE_CLI" get configmap "$DNS_CONFIGMAP" -n "$DNS_NAMESPACE" &>/dev/null; then
		log_warn "CoreDNS configmap not found, skipping CoreDNS configuration"
		log_warn "You may need to manually configure DNS forwarding for example.com"
		return
	fi

	local corefile
	corefile=$("$KUBE_CLI" get configmap "$DNS_CONFIGMAP" -n "$DNS_NAMESPACE" -o jsonpath='{.data.Corefile}')

	if echo "$corefile" | grep -q "example.com:53"; then
		log_info "CoreDNS already configured for example.com"
	else
		register_rollback make -C "$SCRIPT_DIR/.." clean-dns-config
		save_kubernetes_dns_backup "$corefile"
		log_info "Adding example.com zone to CoreDNS (existing zones kept)..."

		local new_corefile
		new_corefile=$(printf 'example.com:53 {\n    forward . %s\n}\n%s' "$fake_dns_ip" "$corefile")
		"$KUBE_CLI" patch configmap "$DNS_CONFIGMAP" -n "$DNS_NAMESPACE" --type=merge \
			-p "$(jq -n --arg cf "$new_corefile" '{data:{Corefile:$cf}}')"

		log_info "CoreDNS configured. Waiting for DNS pods to restart..."
		"$KUBE_CLI" rollout status "$DNS_ROLLOUT_TARGET" -n "$DNS_NAMESPACE" --timeout=60s 2>/dev/null || log_warn "DNS rollout may still be in progress"
	fi
}

display_next_steps() {
	local dns_server="fake-dns-api.${FAKEDNS_NAMESPACE}.svc.cluster.local:53"

	print_header "Fake DNS API Installation Complete!"
	log_info "This fake DNS server accepts RFC2136 update requests and returns success"
	log_info "without actually updating DNS. Perfect for air-gapped DNS-01 testing!"
	echo
	log_info "CoreDNS has been configured to forward example.com queries to fake DNS."
	echo
	echo "Next steps:"
	echo
	echo "1. Update Pebble to use fake DNS server:"
	echo "   oc delete namespace $PEBBLE_NAMESPACE"
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
	echo "   watch oc get certificate -n ${CERT_NAMESPACE:-default}"
	echo
	log_info "DNS server: ${dns_server}"
	echo
}

main() {
	print_header "Install Fake DNS API (Air-gapped)"

	require_cmd "$KUBE_CLI" envsubst jq
	require_cluster
	require_healthy_cluster
	wait_for_namespace_termination "$FAKEDNS_NAMESPACE"

	install_fake_dns
	wait_for_resource "deployment/fake-dns-api" "$FAKEDNS_NAMESPACE" "${DEPLOYMENT_READY_TIMEOUT:-600s}"
	verify_installation
	configure_coredns
	display_next_steps
	clear_rollback
}

main
