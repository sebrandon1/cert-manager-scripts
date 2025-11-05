#!/bin/bash

################################################################################
# Script: install-pebble.sh
# Description: Install Pebble ACME test server for local cert-manager testing
# Reference: https://github.com/letsencrypt/pebble
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/../yaml/pebble"

# Configuration (exported for envsubst)
export PEBBLE_NAMESPACE="${PEBBLE_NAMESPACE:-pebble}"
export DNS_SERVER="${DNS_SERVER:-8.8.8.8:53}"
export PEBBLE_ALWAYS_VALID="${PEBBLE_ALWAYS_VALID:-0}"

# Function to print colored messages
log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

log_note() {
	echo -e "${BLUE}[NOTE]${NC} $1"
}

# Function to print header
print_header() {
	echo
	echo "========================================"
	echo "  Pebble ACME Test Server Installation"
	echo "========================================"
	echo
}

# Function to check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	if ! command -v oc &>/dev/null; then
		log_error "oc command not found. Please install OpenShift CLI."
		exit 1
	fi

	if ! command -v envsubst &>/dev/null; then
		log_error "envsubst command not found. Please install gettext package."
		log_info "  macOS: brew install gettext"
		log_info "  RHEL/Fedora: dnf install gettext"
		exit 1
	fi

	if ! oc whoami &>/dev/null; then
		log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
		exit 1
	fi

	# Check if YAML directory exists
	if [ ! -d "$YAML_DIR" ]; then
		log_error "YAML directory not found: $YAML_DIR"
		exit 1
	fi

	log_info "Prerequisites check passed."
}

# Function to check if Pebble is already installed
check_existing_installation() {
	log_info "Checking for existing Pebble installation..."

	if oc get namespace "$PEBBLE_NAMESPACE" &>/dev/null; then
		log_info "Pebble namespace '$PEBBLE_NAMESPACE' already exists."

		# Check if deployment exists and is healthy
		if oc get deployment pebble -n "$PEBBLE_NAMESPACE" &>/dev/null; then
			local ready_replicas=$(oc get deployment pebble -n "$PEBBLE_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
			local desired_replicas=$(oc get deployment pebble -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

			if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
				log_info "Pebble is already installed and healthy."
				log_info "Installation is idempotent - will verify and ensure components are ready."
				return 0
			else
				log_warn "Pebble exists but may not be healthy. Will attempt to reconcile."
				return 0
			fi
		fi
	fi

	log_info "No existing installation found. Will proceed with fresh installation."
}

# Function to apply YAML with variable substitution
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

# Function to install Pebble
install_pebble() {
	log_info "Installing Pebble ACME test server..."

	# Apply resources in order
	apply_yaml "$YAML_DIR/namespace.yaml" "Namespace"
	apply_yaml "$YAML_DIR/configmap.yaml" "ConfigMap"
	apply_yaml "$YAML_DIR/deployment.yaml" "Deployment"
	apply_yaml "$YAML_DIR/service.yaml" "Service"
	apply_yaml "$YAML_DIR/route.yaml" "Route"

	log_info "Resources applied. Waiting for Pebble to be ready..."
}

# Function to wait for Pebble to be ready
wait_for_pebble() {
	log_info "Waiting for Pebble deployment to be ready..."

	local max_attempts=120 # 10 minutes total
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		if oc get deployment pebble -n "$PEBBLE_NAMESPACE" &>/dev/null; then
			local ready_replicas=$(oc get deployment pebble -n "$PEBBLE_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
			local desired_replicas=$(oc get deployment pebble -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

			if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
				log_info "Pebble deployment is ready!"
				break
			fi

			# Show pod status periodically for better feedback
			if [ $((attempt % 12)) -eq 0 ] && [ $attempt -gt 0 ]; then
				echo
				log_info "Still waiting... Current pod status:"
				oc get pods -n "$PEBBLE_NAMESPACE" --no-headers 2>/dev/null || true
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
		log_error "Timeout waiting for Pebble to be ready."
		log_info "Check the status with: oc get pods -n $PEBBLE_NAMESPACE"
		log_info "Check logs with: oc logs -n $PEBBLE_NAMESPACE deployment/pebble"
		exit 1
	fi

	# Additional wait for pod to be fully ready
	if oc get deployment pebble -n "$PEBBLE_NAMESPACE" &>/dev/null; then
		oc wait --for=condition=available --timeout=60s \
			deployment/pebble \
			-n "$PEBBLE_NAMESPACE" || {
			log_warn "Deployment ready condition not met, but pods may still be working."
		}
	fi
}

# Function to verify installation
verify_installation() {
	log_info "Verifying Pebble installation..."

	# Check pod status
	log_info "Checking pod status..."
	oc get pods -n "$PEBBLE_NAMESPACE"
	echo

	# Check service
	log_info "Checking service..."
	oc get service pebble -n "$PEBBLE_NAMESPACE"
	echo

	# Check route
	log_info "Checking route..."
	oc get route pebble-acme -n "$PEBBLE_NAMESPACE"
	echo

	# Get the route URL
	local route_host=$(oc get route pebble-acme -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

	if [ -n "$route_host" ]; then
		log_info "Pebble ACME directory URL: https://${route_host}/dir"
	fi

	# Get internal service URL
	local service_url="https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:14000/dir"
	log_info "Pebble internal URL: ${service_url}"

	log_info "Installation verification complete!"
}

# Function to display configuration summary
display_configuration() {
	echo
	log_info "========================================"
	log_info "  Pebble Configuration"
	log_info "========================================"
	echo
	echo "Namespace:           $PEBBLE_NAMESPACE"
	echo "DNS Server:          $DNS_SERVER"
	echo "Always Valid:        $PEBBLE_ALWAYS_VALID"
	echo

	if [ "$PEBBLE_ALWAYS_VALID" = "1" ]; then
		log_note "PEBBLE_ALWAYS_VALID=1: All challenges will automatically succeed."
		log_note "This is useful for testing without proper DNS/HTTP challenge setup."
	else
		log_note "PEBBLE_ALWAYS_VALID=0: Challenges must be properly configured."
		log_note "You'll need proper DNS records or HTTP-01 challenge routes."
	fi
	echo
}

# Function to display next steps
display_next_steps() {
	local route_host=$(oc get route pebble-acme -n "$PEBBLE_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
	local service_url="https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:14000/dir"

	echo
	log_info "========================================"
	log_info "  Installation Complete!"
	log_info "========================================"
	echo
	echo "Pebble ACME server is now running!"
	echo
	echo "Next steps:"
	echo
	echo "1. Get Pebble's root CA certificate (for cert-manager to trust):"
	echo "   oc run --rm -i --tty pebble-ca-fetch --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0"
	echo
	echo "   Or save it to a file:"
	echo "   oc run --rm -i pebble-ca-fetch --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0 > pebble-ca.crt"
	echo
	echo "2. Configure a cert-manager ClusterIssuer pointing to Pebble:"
	echo "   ACME Server: ${service_url}"
	if [ -n "$route_host" ]; then
		echo "   External URL: https://${route_host}/dir"
	fi
	echo
	echo "   Note: Use 'skipTLSVerify: true' in your ClusterIssuer since Pebble uses self-signed certs"
	echo
	echo "3. Pebble URLs:"
	echo "   - ACME Directory: ${service_url}"
	echo "   - Management API: https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000"
	echo "   - Root CA: https://pebble.${PEBBLE_NAMESPACE}.svc.cluster.local:15000/roots/0"
	echo
	echo "4. View Pebble logs:"
	echo "   oc logs -n $PEBBLE_NAMESPACE deployment/pebble -f"
	echo
	echo "5. Test ACME directory (from inside cluster):"
	echo "   oc run --rm -i --tty curl-test --image=curlimages/curl --restart=Never -- \\"
	echo "     curl -k ${service_url}"
	echo

	if [ "$PEBBLE_ALWAYS_VALID" = "1" ]; then
		log_note "Remember: PEBBLE_ALWAYS_VALID=1 means all challenges auto-succeed."
		log_note "Great for initial testing, but doesn't validate actual DNS/HTTP setup."
	fi

	echo
	log_info "For more information about Pebble, visit:"
	log_info "https://github.com/letsencrypt/pebble"
	echo
}

# Main execution
main() {
	print_header

	check_prerequisites
	display_configuration
	check_existing_installation
	install_pebble
	wait_for_pebble
	verify_installation
	display_next_steps
}

# Run main function
main
