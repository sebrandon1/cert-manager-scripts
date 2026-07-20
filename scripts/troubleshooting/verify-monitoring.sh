#!/bin/bash

################################################################################
# Script: verify-monitoring.sh
# Description: Verify cert-manager Prometheus monitoring and alert configuration
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
METRICS_PORT="${METRICS_PORT:-9402}"
EXPECTED_ALERTS="CertManagerAbsent CertManagerCertExpirySoon CertManagerCertNotReady CertManagerACMEClientErrors"

pass_count=0
fail_count=0

record_pass() {
	log_success "$1"
	pass_count=$((pass_count + 1))
}

record_fail() {
	log_error "$1"
	fail_count=$((fail_count + 1))
}

check_service_monitor() {
	if "$KUBE_CLI" get servicemonitor cert-manager -n "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
		record_pass "ServiceMonitor 'cert-manager' exists"
	else
		record_fail "ServiceMonitor 'cert-manager' not found"
	fi
}

check_prometheus_rule() {
	local rule_json
	if ! rule_json=$("$KUBE_CLI" get prometheusrule cert-manager-alerts -n "$CERT_MANAGER_NAMESPACE" -o json 2>/dev/null); then
		record_fail "PrometheusRule 'cert-manager-alerts' not found"
		return
	fi
	record_pass "PrometheusRule 'cert-manager-alerts' exists"

	for alert in $EXPECTED_ALERTS; do
		if echo "$rule_json" | jq -e ".spec.groups[].rules[] | select(.alert==\"$alert\")" &>/dev/null; then
			record_pass "Alert rule '$alert' configured"
		else
			record_fail "Alert rule '$alert' missing"
		fi
	done
}

check_metrics_endpoint() {
	local cm_pod
	cm_pod=$("$KUBE_CLI" get pods -n "$CERT_MANAGER_NAMESPACE" -l app=cert-manager \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

	if [ -z "$cm_pod" ]; then
		record_fail "cert-manager controller pod not found"
		return
	fi

	if "$KUBE_CLI" exec "$cm_pod" -n "$CERT_MANAGER_NAMESPACE" -- \
		sh -c "wget -qO- http://localhost:${METRICS_PORT}/metrics 2>/dev/null | head -1" &>/dev/null; then
		record_pass "Metrics endpoint (port $METRICS_PORT) is reachable"
	else
		record_fail "Metrics endpoint (port $METRICS_PORT) is not reachable"
	fi
}

check_metrics_service() {
	if "$KUBE_CLI" get service cert-manager -n "$CERT_MANAGER_NAMESPACE" -o jsonpath='{.spec.ports}' 2>/dev/null |
		grep -q "$METRICS_PORT"; then
		record_pass "cert-manager service exposes metrics port $METRICS_PORT"
	else
		record_fail "cert-manager service does not expose metrics port $METRICS_PORT"
	fi
}

require_cmd jq
require_cluster

print_header "Verify cert-manager Monitoring"
log_info "Namespace: $CERT_MANAGER_NAMESPACE"
echo

if ! check_deployment_exists cert-manager "$CERT_MANAGER_NAMESPACE"; then
	log_error "cert-manager not found in namespace $CERT_MANAGER_NAMESPACE"
	log_info "Install cert-manager first: make install-cert-manager-operator"
	exit 1
fi

check_service_monitor
check_prometheus_rule
check_metrics_service
check_metrics_endpoint

echo
print_summary \
	"Passed" "$pass_count" \
	"Failed" "$fail_count" \
	"Total" "$((pass_count + fail_count))"

if [ "$fail_count" -gt 0 ]; then
	echo
	log_warn "Some checks failed. Run 'make install-monitoring' to set up monitoring."
	exit 1
fi
