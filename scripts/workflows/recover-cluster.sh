#!/bin/bash

################################################################################
# Script: recover-cluster.sh
# Description: Attempt to recover CRC cluster from common failure states
# Used by: CI workflows when cluster becomes unresponsive
################################################################################

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

print_header "CRC Cluster Recovery Attempt"

# Test 1: Check if DNS resolution is working
log_info "Checking DNS resolution..."
API_HOST=$("$KUBE_CLI" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed 's|https://||' | cut -d: -f1 || echo "")

if [ -z "$API_HOST" ]; then
	log_error "Cannot determine API server hostname"
	exit 1
fi

if ! getent hosts "$API_HOST" &>/dev/null; then
	log_warn "DNS resolution failed for $API_HOST"
	log_info "Attempting to refresh DNS..."

	# Try to ping the host to refresh DNS cache
	ping -c 1 "$API_HOST" &>/dev/null || true

	if retry 3 5 getent hosts "$API_HOST"; then
		log_info "✅ DNS resolution recovered"
	else
		log_error "❌ DNS resolution still failing"
		log_error "Cluster may need restart"
		exit 1
	fi
fi

# Test 2: Check if we can authenticate
log_info "Checking cluster authentication..."
if [[ "$KUBE_CLI" == "oc" ]]; then
	auth_cmd=("$KUBE_CLI" whoami)
else
	auth_cmd=("$KUBE_CLI" get namespace default)
fi
if ! "${auth_cmd[@]}" &>/dev/null; then
	log_warn "Cannot authenticate with cluster"
	log_info "Attempting to refresh authentication..."

	# Try to force a token refresh
	"$KUBE_CLI" version &>/dev/null || true

	if retry 3 3 "${auth_cmd[@]}"; then
		log_info "✅ Authentication recovered"
	else
		log_error "❌ Authentication still failing"
		exit 1
	fi
fi

# Test 3: Check API server responsiveness
log_info "Checking API server responsiveness..."
if retry 5 5 "$KUBE_CLI" get namespace default; then
	log_info "✅ API server is responsive"
else
	log_error "❌ API server not responsive after 5 attempts"
	exit 1
fi

print_header "Cluster Recovery Successful"
log_info "Cluster appears to be functional again"
echo
