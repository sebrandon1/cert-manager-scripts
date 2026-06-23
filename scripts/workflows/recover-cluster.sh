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
API_HOST=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed 's|https://||' | cut -d: -f1 || echo "")

if [ -z "$API_HOST" ]; then
	log_error "Cannot determine API server hostname"
	exit 1
fi

if ! getent hosts "$API_HOST" &>/dev/null; then
	log_warn "DNS resolution failed for $API_HOST"
	log_info "Attempting to refresh DNS..."

	# Try to ping the host to refresh DNS cache
	ping -c 1 "$API_HOST" &>/dev/null || true

	# Wait a bit for DNS to propagate
	sleep 5

	if getent hosts "$API_HOST" &>/dev/null; then
		log_info "✅ DNS resolution recovered"
	else
		log_error "❌ DNS resolution still failing"
		log_error "Cluster may need restart"
		exit 1
	fi
fi

# Test 2: Check if we can authenticate
log_info "Checking cluster authentication..."
if ! oc whoami &>/dev/null; then
	log_warn "Cannot authenticate with cluster"
	log_info "Attempting to refresh authentication..."

	# Try to force a token refresh
	oc version &>/dev/null || true
	sleep 2

	if oc whoami &>/dev/null; then
		log_info "✅ Authentication recovered"
	else
		log_error "❌ Authentication still failing"
		exit 1
	fi
fi

# Test 3: Check API server responsiveness
log_info "Checking API server responsiveness..."
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
	if oc get namespace default &>/dev/null; then
		log_info "✅ API server is responsive"
		break
	else
		RETRY_COUNT=$((RETRY_COUNT + 1))
		log_warn "API server not responding (attempt $RETRY_COUNT/$MAX_RETRIES)"
		sleep 5
	fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
	log_error "❌ API server not responsive after $MAX_RETRIES attempts"
	exit 1
fi

print_header "Cluster Recovery Successful"
log_info "Cluster appears to be functional again"
echo
