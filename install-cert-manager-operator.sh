#!/bin/bash

################################################################################
# Script: install-cert-manager-operator.sh
# Description: Install cert-manager Operator for Red Hat OpenShift
# Reference: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="${SCRIPT_DIR}/yaml/cert-manager-operator"

# Configuration (exported for envsubst)
export OPERATOR_NAMESPACE="cert-manager-operator"
export CERT_MANAGER_NAMESPACE="cert-manager"
export OPERATOR_NAME="openshift-cert-manager-operator"
export CHANNEL="stable-v1"

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

# Function to check if oc is installed and user is logged in
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v oc &> /dev/null; then
        log_error "oc command not found. Please install OpenShift CLI."
        exit 1
    fi
    
    if ! command -v envsubst &> /dev/null; then
        log_error "envsubst command not found. Please install gettext package."
        log_info "  macOS: brew install gettext"
        log_info "  RHEL/Fedora: dnf install gettext"
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    
    # Check if user has cluster-admin privileges
    if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
        log_error "Cluster-admin privileges required. Please ensure you have the necessary permissions."
        exit 1
    fi
    
    # Check if YAML directory exists
    if [ ! -d "$YAML_DIR" ]; then
        log_error "YAML directory not found: $YAML_DIR"
        exit 1
    fi
    
    log_info "Prerequisites check passed."
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=$1
    
    if oc get namespace "$namespace" &> /dev/null; then
        log_info "Namespace '$namespace' already exists."
    else
        log_info "Creating namespace '$namespace'..."
        oc create namespace "$namespace"
        log_info "Namespace '$namespace' created successfully."
    fi
}

# Function to check if operator is already installed
check_existing_installation() {
    log_info "Checking for existing cert-manager-operator installation..."
    
    if oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" &> /dev/null; then
        log_info "cert-manager-operator subscription already exists."
        
        # Get current version/channel
        local current_channel=$(oc get subscription "$OPERATOR_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.spec.channel}')
        log_info "Current channel: $current_channel"
        
        # Check if it's healthy
        if oc get csv -n "$OPERATOR_NAMESPACE" | grep -q "cert-manager.*Succeeded"; then
            log_info "Operator is already installed and healthy."
            log_info "Installation is idempotent - will verify and ensure components are ready."
            return 0
        else
            log_warn "Operator exists but may not be healthy. Will attempt to reconcile."
            return 0
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

# Function to install the operator
install_operator() {
    log_info "Installing cert-manager Operator for Red Hat OpenShift..."
    
    # Create OperatorGroup
    apply_yaml "$YAML_DIR/operatorgroup.yaml" "OperatorGroup"
    
    # Create Subscription
    apply_yaml "$YAML_DIR/subscription.yaml" "Subscription"
    
    log_info "Resources applied. Waiting for operator installation to complete..."
}

# Function to wait for operator to be ready
wait_for_operator() {
    log_info "Waiting for cert-manager-operator to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if CSV is present and successful
        if oc get csv -n "$OPERATOR_NAMESPACE" 2>/dev/null | grep -q "cert-manager.*Succeeded"; then
            log_info "Operator CSV is in Succeeded phase."
            break
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
        log_error "Timeout waiting for operator CSV to be ready."
        log_info "Check the status with: oc get csv -n $OPERATOR_NAMESPACE"
        log_info "Check operator logs with: oc logs -n $OPERATOR_NAMESPACE deployment/cert-manager-operator-controller-manager"
        exit 1
    fi
    
    # Wait for operator deployment to be ready
    log_info "Waiting for operator deployment to be ready..."
    if oc get deployment cert-manager-operator-controller-manager -n "$OPERATOR_NAMESPACE" &> /dev/null; then
        oc wait --for=condition=available --timeout=300s \
            deployment/cert-manager-operator-controller-manager \
            -n "$OPERATOR_NAMESPACE" || {
            log_error "Operator deployment failed to become ready."
            exit 1
        }
    else
        log_warn "Operator deployment not found yet, but CSV is ready."
    fi
    
    log_info "Operator is ready!"
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check operator pod
    log_info "Checking operator pod status..."
    oc get pods -n "$OPERATOR_NAMESPACE"
    
    # Check CSV
    log_info "Checking ClusterServiceVersion..."
    oc get csv -n "$OPERATOR_NAMESPACE"
    
    # Check if cert-manager namespace exists (created by operator)
    if oc get namespace "$CERT_MANAGER_NAMESPACE" &> /dev/null; then
        log_info "cert-manager namespace exists."
        
        # Check cert-manager deployments
        log_info "Checking cert-manager components..."
        oc get deployments -n "$CERT_MANAGER_NAMESPACE"
    else
        log_warn "cert-manager namespace not yet created. The operator will create it."
    fi
    
    log_info "Installation verification complete!"
}

# Function to display next steps
display_next_steps() {
    echo
    log_info "========================================"
    log_info "Installation completed successfully!"
    log_info "========================================"
    echo
    echo "Next steps:"
    echo "1. Verify the operator is running:"
    echo "   oc get pods -n $OPERATOR_NAMESPACE"
    echo
    echo "2. Check cert-manager components (may take a moment to appear):"
    echo "   oc get pods -n $CERT_MANAGER_NAMESPACE"
    echo
    echo "3. Configure an issuer (ACME, CA, or self-signed):"
    echo "   https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift#cert-manager-acme-dns01"
    echo
    echo "4. Create certificates:"
    echo "   https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift#cert-manager-create-certificates"
    echo
}

# Main execution
main() {
    log_info "Starting cert-manager Operator installation..."
    echo
    
    check_prerequisites
    check_existing_installation
    create_namespace "$OPERATOR_NAMESPACE"
    install_operator
    wait_for_operator
    verify_installation
    display_next_steps
}

# Run main function
main

