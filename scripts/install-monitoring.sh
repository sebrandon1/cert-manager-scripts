#!/bin/bash

################################################################################
# Script: install-monitoring.sh
# Description: Deploy cert-manager Prometheus monitoring (ServiceMonitor + alerts)
#
# Prerequisites:
#   - cert-manager operator installed
#   - User workload monitoring enabled (enableUserWorkload: true)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

YAML_DIR="${SCRIPT_DIR}/../yaml/monitoring"

export CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"

check_user_workload_monitoring() {
	log_info "Checking if user workload monitoring is enabled..."

	local uwm_enabled
	uwm_enabled=$(oc get configmap cluster-monitoring-config -n openshift-monitoring \
		-o jsonpath='{.data.config\.yaml}' 2>/dev/null || echo "")

	if echo "$uwm_enabled" | grep -q "enableUserWorkload.*true"; then
		log_success "User workload monitoring is enabled."
	else
		log_warn "User workload monitoring may not be enabled."
		log_info "To enable, apply this ConfigMap:"
		echo
		echo "  oc apply -f - <<EOF"
		echo "  apiVersion: v1"
		echo "  kind: ConfigMap"
		echo "  metadata:"
		echo "    name: cluster-monitoring-config"
		echo "    namespace: openshift-monitoring"
		echo "  data:"
		echo "    config.yaml: |"
		echo "      enableUserWorkload: true"
		echo "  EOF"
		echo
		read -p "Continue anyway? (y/N): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			log_info "Cancelled."
			exit 0
		fi
	fi
}

check_existing_resources() {
	log_info "Checking for existing monitoring resources..."

	local exists=false

	if oc get servicemonitor cert-manager -n "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
		log_warn "ServiceMonitor 'cert-manager' already exists."
		exists=true
	fi

	if oc get prometheusrule cert-manager-alerts -n "$CERT_MANAGER_NAMESPACE" &>/dev/null; then
		log_warn "PrometheusRule 'cert-manager-alerts' already exists."
		exists=true
	fi

	if [ "$exists" = true ]; then
		echo
		read -p "Overwrite existing resources? (y/N): " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			log_info "Keeping existing resources."
			exit 0
		fi
	fi
}

install_service_monitor() {
	log_info "Step 1/2: Creating ServiceMonitor..."
	apply_yaml_template "$YAML_DIR/service-monitor.yaml" "ServiceMonitor"
	log_success "ServiceMonitor created."
}

install_prometheus_rules() {
	log_info "Step 2/2: Creating PrometheusRule alerts..."
	apply_yaml_template "$YAML_DIR/prometheus-rules.yaml" "PrometheusRule"
	log_success "PrometheusRule created."
}

verify_monitoring() {
	log_info "Verifying monitoring resources..."
	echo

	log_info "ServiceMonitor:"
	oc get servicemonitor -n "$CERT_MANAGER_NAMESPACE" 2>/dev/null || echo "  No ServiceMonitors found"
	echo

	log_info "PrometheusRule:"
	oc get prometheusrule -n "$CERT_MANAGER_NAMESPACE" 2>/dev/null || echo "  No PrometheusRules found"
	echo
}

display_next_steps() {
	echo
	log_success "cert-manager monitoring configured!"
	echo
	echo "Alerts configured:"
	echo "  - CertManagerAbsent         (critical) cert-manager not scraped for 15m"
	echo "  - CertManagerCertExpirySoon  (warning)  certificate expiring within 21 days"
	echo "  - CertManagerCertNotReady    (warning)  certificate not ready for 10m"
	echo "  - CertManagerACMEClientErrors  (warning) ACME 4xx errors detected"
	echo
	echo "Next steps:"
	echo
	echo "1. Verify metrics are being scraped:"
	echo "   oc get servicemonitor -n $CERT_MANAGER_NAMESPACE"
	echo
	echo "2. Check alert rules in the OpenShift console:"
	echo "   Observe > Alerting > Alerting Rules"
	echo
	echo "3. Verify cert-manager metrics (from a Prometheus pod):"
	echo "   curl http://cert-manager.$CERT_MANAGER_NAMESPACE.svc:9402/metrics"
	echo
}

main() {
	print_header "Install cert-manager Monitoring"

	require_cmd oc envsubst
	require_cluster

	if ! oc get deployment -n "$CERT_MANAGER_NAMESPACE" cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		log_info "  Run: make install-cert-manager-operator"
		exit 1
	fi

	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	print_summary \
		"Namespace" "$CERT_MANAGER_NAMESPACE"

	check_user_workload_monitoring
	check_existing_resources
	install_service_monitor
	install_prometheus_rules
	verify_monitoring
	display_next_steps
}

main
