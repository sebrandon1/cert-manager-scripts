#!/bin/bash

################################################################################
# Script: display-component-status.sh
# Description: Display component status (safe for cluster failures)
# Used by: CI workflows to show status even when cluster is unhealthy
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

echo
echo "========================================"
echo "  Component Status"
echo "========================================"
echo

# Check if cluster is accessible
if ! oc whoami &>/dev/null; then
	log_error "❌ Cluster is not accessible"
	log_warn "Cannot display component status - cluster connection failed"
	echo
	log_info "Cluster may be:"
	echo "  • Down or restarting"
	echo "  • DNS resolution failure"
	echo "  • Authentication issues"
	echo
	exit 0
fi

log_info "Cluster is accessible, displaying component status..."
echo

echo "cert-manager pods:"
oc get pods -n cert-manager || log_warn "Cannot retrieve cert-manager pods"
echo ""
echo "Pebble pods:"
oc get pods -n pebble || log_warn "Cannot retrieve Pebble pods"
echo ""
echo "ClusterIssuer status:"
oc get clusterissuer -o wide || log_warn "Cannot retrieve ClusterIssuers"
echo ""
echo "Certificate status:"
oc get certificate -n default || log_warn "Cannot retrieve Certificates"
echo ""
echo "CertificateRequest status:"
oc get certificaterequest -n default || log_warn "Cannot retrieve CertificateRequests"
echo ""
echo "Order status:"
oc get order -n default || log_warn "Cannot retrieve Orders"
echo ""
echo "Challenge status:"
oc get challenge -n default || log_warn "Cannot retrieve Challenges"
echo ""
echo "Recent cert-manager logs:"
oc logs -n cert-manager deployment/cert-manager --tail=30 || log_warn "Cannot retrieve cert-manager logs"
echo
echo "========================================"
echo "  Status Display Complete"
echo "========================================"
echo
