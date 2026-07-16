#!/bin/bash
################################################################################
# Script: preflight-check.sh
# Description: Validate all dependencies and prerequisites before running workflows
################################################################################
#
# Usage: ./scripts/preflight-check.sh
#        make preflight

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
check_help "$@" && exit 0

print_header "CERT-MANAGER SCRIPTS - PREFLIGHT CHECK"

FAILED=0
WARNINGS=0

# ============================================================================
# Required CLI Tools
# ============================================================================
log_info "Checking required CLI tools..."

check_cmd() {
	local cmd="$1"
	local install_hint="${2:-}"

	if command -v "$cmd" &>/dev/null; then
		local version
		case "$cmd" in
		oc) version=$(oc version --client 2>/dev/null | head -1 || echo "unknown") ;;
		envsubst) version=$(envsubst --version 2>/dev/null | head -1 || echo "installed") ;;
		shfmt) version=$(shfmt --version 2>/dev/null || echo "installed") ;;
		shellcheck) version=$(shellcheck --version 2>/dev/null | grep version: || echo "installed") ;;
		*) version="installed" ;;
		esac
		log_success "$cmd: $version"
		return 0
	else
		log_error "$cmd: NOT FOUND"
		[[ -n "$install_hint" ]] && echo "       $install_hint"
		FAILED=1
		return 1
	fi
}

# Required tools
check_cmd oc "Install: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
check_cmd envsubst "Install: brew install gettext (macOS) or dnf install gettext (Fedora)"

# Optional tools (for development)
echo ""
log_info "Checking optional development tools..."

if ! check_cmd shfmt "Install: brew install shfmt (macOS) or go install mvdan.cc/sh/v3/cmd/shfmt@latest"; then
	FAILED=$((FAILED - 1)) # Don't count as failure
	WARNINGS=$((WARNINGS + 1))
fi

if ! check_cmd shellcheck "Install: brew install shellcheck (macOS) or dnf install ShellCheck (Fedora)"; then
	FAILED=$((FAILED - 1)) # Don't count as failure
	WARNINGS=$((WARNINGS + 1))
fi

# ============================================================================
# Cluster Connectivity
# ============================================================================
echo ""
log_info "Checking cluster connectivity..."

if command -v oc &>/dev/null; then
	if oc whoami &>/dev/null 2>&1; then
		user=$(oc whoami)
		server=$(oc whoami --show-server 2>/dev/null || echo "unknown")
		log_success "Logged in as: $user"
		log_success "Cluster: $server"

		# Check cluster-admin privileges
		if oc auth can-i '*' '*' --all-namespaces &>/dev/null 2>&1; then
			log_success "Cluster-admin privileges: yes"
		else
			log_warn "Cluster-admin privileges: no (some operations may fail)"
			WARNINGS=$((WARNINGS + 1))
		fi
		# Check OCP version (4.14+ required for cert-manager operator)
		if oc get clusterversion version &>/dev/null 2>&1; then
			ocp_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
			ocp_major_minor=$(echo "$ocp_version" | grep -oE '^[0-9]+\.[0-9]+')
			log_success "OpenShift version: $ocp_version"
			if [[ -n "$ocp_major_minor" ]]; then
				ocp_minor=$(echo "$ocp_major_minor" | cut -d. -f2)
				if [[ "$ocp_minor" -lt 14 ]]; then
					log_warn "OpenShift 4.14+ recommended for cert-manager operator"
					WARNINGS=$((WARNINGS + 1))
				fi
			fi
		fi
	else
		log_warn "Not connected to cluster (optional for preflight)"
		log_info "Run 'oc login' before running scripts that require cluster access"
		WARNINGS=$((WARNINGS + 1))
	fi
else
	log_error "Cannot check cluster: oc not installed"
fi

# ============================================================================
# YAML Directory Check
# ============================================================================
echo ""
log_info "Checking project structure..."

YAML_DIR="$SCRIPT_DIR/yaml/cert-manager-operator"
if [[ -d "$YAML_DIR" ]]; then
	yaml_count=$(find "$YAML_DIR" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
	log_success "YAML templates directory: $YAML_DIR ($yaml_count files)"
else
	log_error "YAML templates directory not found: $YAML_DIR"
	FAILED=$((FAILED + 1))
fi

# Check lib/common.sh exists
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
	log_success "Shared library: lib/common.sh"
else
	log_warn "Shared library not found: lib/common.sh"
	WARNINGS=$((WARNINGS + 1))
fi

# Check .env file
if [[ -f "$SCRIPT_DIR/.env" ]]; then
	log_success "Environment config: .env (loaded)"
elif [[ -f "$SCRIPT_DIR/.env.example" ]]; then
	log_info "Environment config: .env.example exists (copy to .env to customize)"
else
	log_info "Environment config: not configured (using defaults)"
fi

# ============================================================================
# Summary
# ============================================================================
print_header "SUMMARY"

if [[ $FAILED -eq 0 && $WARNINGS -eq 0 ]]; then
	log_success "All checks passed!"
	echo ""
	echo "You're ready to run cert-manager-scripts."
	echo "Start with: make install-cert-manager-operator"
	exit 0
elif [[ $FAILED -eq 0 ]]; then
	log_warn "Passed with $WARNINGS warning(s)"
	echo ""
	echo "You can proceed, but some features may be limited."
	exit 0
else
	log_error "Failed with $FAILED error(s) and $WARNINGS warning(s)"
	echo ""
	echo "Please install missing dependencies before proceeding."
	exit 1
fi
