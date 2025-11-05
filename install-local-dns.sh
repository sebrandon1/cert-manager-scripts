#!/bin/bash

################################################################################
# Script: install-local-dns.sh
# Description: Install acme-dns for local DNS-01 challenge testing
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
YAML_DIR="${SCRIPT_DIR}/yaml/acme-dns"

# Configuration (exported for envsubst)
export ACMEDNS_NAMESPACE="${ACMEDNS_NAMESPACE:-acme-dns}"

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
    echo "  Install Local DNS Server (acme-dns)"
    echo "========================================"
    echo
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v oc &> /dev/null; then
        log_error "oc command not found. Please install OpenShift CLI."
        exit 1
    fi
    
    if ! command -v envsubst &> /dev/null; then
        log_error "envsubst command not found. Please install gettext package."
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    
    if [ ! -d "$YAML_DIR" ]; then
        log_error "YAML directory not found: $YAML_DIR"
        exit 1
    fi
    
    log_info "Prerequisites check passed."
}

# Function to check existing installation
check_existing_installation() {
    log_info "Checking for existing acme-dns installation..."
    
    if oc get namespace "$ACMEDNS_NAMESPACE" &> /dev/null; then
        log_info "acme-dns namespace already exists."
        
        if oc get deployment acme-dns -n "$ACMEDNS_NAMESPACE" &> /dev/null; then
            local ready_replicas=$(oc get deployment acme-dns -n "$ACMEDNS_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$ready_replicas" != "0" ]; then
                log_info "acme-dns is already installed and running."
                log_info "Installation is idempotent - will verify components."
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
    envsubst < "$yaml_file" | oc apply -f -
}

# Function to install acme-dns
install_acme_dns() {
    log_info "Installing acme-dns..."
    
    apply_yaml "$YAML_DIR/namespace.yaml" "Namespace"
    apply_yaml "$YAML_DIR/configmap.yaml" "ConfigMap"
    apply_yaml "$YAML_DIR/deployment.yaml" "Deployment"
    apply_yaml "$YAML_DIR/service.yaml" "Service"
    
    log_info "Resources applied. Waiting for acme-dns to be ready..."
}

# Function to wait for acme-dns
wait_for_acme_dns() {
    log_info "Waiting for acme-dns deployment to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if oc get deployment acme-dns -n "$ACMEDNS_NAMESPACE" &> /dev/null; then
            local ready_replicas=$(oc get deployment acme-dns -n "$ACMEDNS_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$ready_replicas" != "0" ]; then
                log_info "acme-dns is ready!"
                break
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
        log_error "Timeout waiting for acme-dns to be ready."
        log_info "Check status: oc get pods -n $ACMEDNS_NAMESPACE"
        exit 1
    fi
    
    if oc get deployment acme-dns -n "$ACMEDNS_NAMESPACE" &> /dev/null; then
        oc wait --for=condition=available --timeout=60s \
            deployment/acme-dns \
            -n "$ACMEDNS_NAMESPACE" || {
            log_warn "Deployment condition not met, but pods may be working."
        }
    fi
}

# Function to verify installation
verify_installation() {
    log_info "Verifying acme-dns installation..."
    
    log_info "Checking pods..."
    oc get pods -n "$ACMEDNS_NAMESPACE"
    echo
    
    log_info "Checking service..."
    oc get service acme-dns -n "$ACMEDNS_NAMESPACE"
    echo
    
    log_info "Installation verification complete!"
}

# Function to display next steps
display_next_steps() {
    local acmedns_api="http://acme-dns.${ACMEDNS_NAMESPACE}.svc.cluster.local:8080"
    local acmedns_dns="acme-dns.${ACMEDNS_NAMESPACE}.svc.cluster.local"
    
    echo
    log_info "========================================"
    log_info "  acme-dns Installation Complete!"
    log_info "========================================"
    echo
    echo "acme-dns is now running!"
    echo
    echo "Next steps:"
    echo
    echo "1. Update Pebble to use acme-dns for validation:"
    echo "   oc delete namespace pebble"
    echo "   DNS_SERVER=${acmedns_dns}:53 PEBBLE_ALWAYS_VALID=1 make install-pebble"
    echo
    echo "2. Install cert-manager webhook for acme-dns:"
    echo "   make install-acmedns-webhook"
    echo
    echo "3. Create a DNS-01 ClusterIssuer:"
    echo "   make create-dns01-issuer"
    echo
    echo "4. Test with a wildcard certificate:"
    echo "   make create-wildcard-cert"
    echo
    echo "acme-dns URLs:"
    echo "  - API: ${acmedns_api}"
    echo "  - DNS: ${acmedns_dns}:53"
    echo
    log_note "acme-dns provides a REST API for creating/updating DNS TXT records"
    log_note "cert-manager will use this API for DNS-01 challenges"
    echo
}

# Main execution
main() {
    print_header
    check_prerequisites
    check_existing_installation
    install_acme_dns
    wait_for_acme_dns
    verify_installation
    display_next_steps
}

# Run main function
main

