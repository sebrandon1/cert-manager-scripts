#!/bin/bash

################################################################################
# Script: verify-cluster-access.sh
# Description: Comprehensive CRC cluster health check
# Used by: CI workflows to verify cluster is stable before running tests
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo
echo "========================================"
echo "  CRC Cluster Health Check"
echo "========================================"
echo

# Test 1: Check oc command is available
log_info "Checking oc CLI availability..."
if ! command -v oc &>/dev/null; then
	log_error "oc command not found"
	exit 1
fi
oc version --client
echo

# Test 2: Check DNS resolution for API server
log_info "Checking API server DNS resolution..."
API_HOST=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed 's|https://||' | cut -d: -f1)
if [ -z "$API_HOST" ]; then
	log_error "Could not determine API server hostname from kubeconfig"
	exit 1
fi
log_info "API server hostname: $API_HOST"

if getent hosts "$API_HOST" &>/dev/null; then
	log_info "✅ DNS resolution successful"
	API_IP=$(getent hosts "$API_HOST" | awk '{print $1}')
	log_info "Resolved to: $API_IP"
else
	log_error "❌ Cannot resolve $API_HOST"
	log_error "DNS resolution failed - cluster may be unreachable"
	exit 1
fi
echo

# Test 3: Check KUBECONFIG
log_info "Checking KUBECONFIG..."
if [ -z "${KUBECONFIG:-}" ]; then
	log_warn "KUBECONFIG not set, using default ~/.kube/config"
else
	log_info "KUBECONFIG: $KUBECONFIG"
	if [ ! -f "$KUBECONFIG" ]; then
		log_error "KUBECONFIG file does not exist: $KUBECONFIG"
		exit 1
	fi
fi
echo

# Test 4: Check authentication
log_info "Checking cluster authentication..."
if oc whoami &>/dev/null; then
	USERNAME=$(oc whoami 2>/dev/null)
	log_info "✅ Authenticated as: $USERNAME"
else
	log_error "❌ Cannot authenticate with cluster"
	log_error "Authentication failed - cluster may be down or credentials invalid"
	exit 1
fi
echo

# Test 5: Check API server reachability
log_info "Checking API server reachability..."
if oc version &>/dev/null; then
	log_info "✅ API server is reachable"
	oc version | grep -E "Server Version|Kubernetes Version" || true
else
	log_error "❌ Cannot reach API server"
	exit 1
fi
echo

# Test 6: Check cluster nodes
log_info "Checking cluster nodes..."
NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l | xargs)
if [ "$NODE_COUNT" -gt 0 ]; then
	log_info "✅ Cluster has $NODE_COUNT node(s)"
	oc get nodes
else
	log_error "❌ No nodes found in cluster"
	exit 1
fi
echo

# Test 7: Check node readiness
log_info "Checking node readiness..."
NOT_READY=$(oc get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l | xargs)
if [ "$NOT_READY" -eq 0 ]; then
	log_info "✅ All nodes are Ready"
else
	log_warn "⚠️  $NOT_READY node(s) not ready"
	oc get nodes | grep -v " Ready " || true
fi
echo

# Test 8: Check critical cluster operators
log_info "Checking critical cluster operators..."
DEGRADED_OPS=$(oc get clusteroperators --no-headers 2>/dev/null | awk '$3=="True" || $4=="True" || $5=="True"' | wc -l | xargs)
if [ "$DEGRADED_OPS" -eq 0 ]; then
	log_info "✅ No degraded cluster operators"
else
	log_warn "⚠️  $DEGRADED_OPS cluster operator(s) degraded"
	oc get clusteroperators | grep -E "DEGRADED.*True|PROGRESSING.*True|AVAILABLE.*False" || true
	log_warn "Continuing despite degraded operators (may cause test issues)"
fi
echo

# Test 9: Quick API responsiveness check
log_info "Checking API responsiveness..."
START_TIME=$(date +%s)
if oc get namespace default &>/dev/null; then
	END_TIME=$(date +%s)
	DURATION=$((END_TIME - START_TIME))
	log_info "✅ API responded in ${DURATION}s"
	if [ "$DURATION" -gt 5 ]; then
		log_warn "⚠️  API response time is slow (${DURATION}s)"
	fi
else
	log_error "❌ API did not respond to test query"
	exit 1
fi
echo

echo "========================================"
echo "  ✅ Cluster Health Check Passed"
echo "========================================"
echo
log_info "Cluster is ready for testing"
echo
