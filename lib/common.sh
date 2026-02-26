#!/bin/bash
# common.sh - Shared functions for cert-manager-scripts
#
# Usage: Source this file at the top of your scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
#
# Features:
#   - Colorized logging with log levels (LOG_LEVEL=quiet|error|warn|info|debug)
#   - Dependency checking (require_cmd)
#   - Cluster connectivity validation (require_cluster)
#   - .env file loading (load_env)
#   - Cleanup trap setup (setup_cleanup)
#   - Retry logic with exponential backoff (retry)
#   - Summary output (print_summary)

set -euo pipefail

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================
# Only use colors if terminal supports it
if [[ -t 1 ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	BOLD='\033[1m'
	NC='\033[0m' # No Color
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	BOLD=''
	NC=''
fi

# ============================================================================
# LOG LEVELS
# ============================================================================
# Log levels: 0=quiet, 1=error, 2=warn, 3=info (default), 4=debug
# Set via environment variable: LOG_LEVEL=quiet|error|warn|info|debug
_LOG_LEVEL="${LOG_LEVEL:-3}"

# Normalize string log levels to numeric (portable for bash 3.x on macOS)
_LOG_LEVEL_LOWER=$(echo "$_LOG_LEVEL" | tr '[:upper:]' '[:lower:]')
case "$_LOG_LEVEL_LOWER" in
quiet | q) _LOG_LEVEL=0 ;;
error | e) _LOG_LEVEL=1 ;;
warn | w) _LOG_LEVEL=2 ;;
info | i) _LOG_LEVEL=3 ;;
debug | d) _LOG_LEVEL=4 ;;
[0-4]) ;; # Already numeric
*)
	echo "[WARN] Invalid LOG_LEVEL '$_LOG_LEVEL', using 'info'" >&2
	_LOG_LEVEL=3
	;;
esac
readonly LOG_LEVEL=$_LOG_LEVEL

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
log_error() {
	[[ $LOG_LEVEL -ge 1 ]] && echo -e "${RED}[ERROR]${NC} $*" >&2 || true
}

log_warn() {
	[[ $LOG_LEVEL -ge 2 ]] && echo -e "${YELLOW}[WARN]${NC} $*" || true
}

log_info() {
	[[ $LOG_LEVEL -ge 3 ]] && echo -e "${BLUE}[INFO]${NC} $*" || true
}

log_success() {
	[[ $LOG_LEVEL -ge 3 ]] && echo -e "${GREEN}[SUCCESS]${NC} $*" || true
}

log_debug() {
	[[ $LOG_LEVEL -ge 4 ]] && echo -e "${BOLD}[DEBUG]${NC} $*" || true
}

# ============================================================================
# DEPENDENCY CHECKING
# ============================================================================
# Check if required commands are available
# Usage: require_cmd oc yq jq
require_cmd() {
	for cmd in "$@"; do
		if ! command -v "$cmd" &>/dev/null; then
			log_error "Required command not found: '$cmd'"
			case "$cmd" in
			oc) log_info "  Install OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html" ;;
			yq) log_info "  Install yq: brew install yq (macOS) or https://github.com/mikefarah/yq" ;;
			jq) log_info "  Install jq: brew install jq (macOS) or apt install jq (Linux)" ;;
			envsubst) log_info "  Install gettext: brew install gettext (macOS) or dnf install gettext (Fedora)" ;;
			esac
			exit 1
		fi
	done
}

# ============================================================================
# CLUSTER CONNECTIVITY
# ============================================================================
# Verify cluster connectivity
# Usage: require_cluster
require_cluster() {
	if ! command -v oc &>/dev/null; then
		log_error "OpenShift CLI (oc) not found."
		exit 1
	fi

	if ! oc whoami &>/dev/null 2>&1; then
		log_error "Not connected to OpenShift cluster. Run 'oc login' first."
		exit 1
	fi

	log_debug "Connected to cluster as: $(oc whoami)"
	log_debug "Cluster: $(oc whoami --show-server 2>/dev/null || echo 'unknown')"
}

# ============================================================================
# ENVIRONMENT LOADING
# ============================================================================
# Load .env file if present
# Usage: load_env [optional_path]
load_env() {
	local env_file="${1:-.env}"

	# Look for .env in script directory or parent
	if [[ ! -f "$env_file" && -n "${SCRIPT_DIR:-}" ]]; then
		if [[ -f "$SCRIPT_DIR/.env" ]]; then
			env_file="$SCRIPT_DIR/.env"
		elif [[ -f "$SCRIPT_DIR/../.env" ]]; then
			env_file="$SCRIPT_DIR/../.env"
		fi
	fi

	if [[ -f "$env_file" ]]; then
		log_debug "Loading environment from: $env_file"
		set -a
		# shellcheck source=/dev/null
		source "$env_file"
		set +a
	fi
}

# ============================================================================
# CLEANUP HANDLING
# ============================================================================
# Track start time and set up cleanup trap
# Usage: setup_cleanup
_START_TIME=""
_TEMP_FILES=()

setup_cleanup() {
	_START_TIME=$(date +%s)

	cleanup() {
		local exit_code=$?
		local duration=$(($(date +%s) - _START_TIME))

		# Clean up temp files
		for f in "${_TEMP_FILES[@]:-}"; do
			[[ -f "$f" ]] && rm -f "$f"
		done

		if [[ $LOG_LEVEL -ge 3 ]]; then
			log_info "Duration: ${duration}s"
		fi
		exit $exit_code
	}
	trap cleanup EXIT
}

# Register a temp file for cleanup
# Usage: register_temp_file /path/to/file
register_temp_file() {
	_TEMP_FILES+=("$1")
}

# ============================================================================
# RETRY LOGIC
# ============================================================================
# Retry a command with exponential backoff
# Usage: retry <max_attempts> <initial_delay_seconds> <command...>
# Example: retry 3 5 oc get pods
retry() {
	local max_attempts="$1"
	local delay="$2"
	shift 2

	local attempt=1
	while true; do
		if "$@"; then
			return 0
		fi

		if [[ $attempt -ge $max_attempts ]]; then
			log_error "Command failed after $max_attempts attempts: $*"
			return 1
		fi

		log_warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
		sleep "$delay"
		delay=$((delay * 2)) # Exponential backoff
		attempt=$((attempt + 1))
	done
}

# ============================================================================
# SUMMARY OUTPUT
# ============================================================================
# Print a formatted summary table
# Usage: print_summary "Key1" "Value1" "Key2" "Value2" ...
print_summary() {
	echo ""
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "  SUMMARY"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	while [[ $# -ge 2 ]]; do
		printf "  %-25s %s\n" "$1:" "$2"
		shift 2
	done
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo ""
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
# Check if running with cluster-admin privileges
require_cluster_admin() {
	require_cluster
	if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
		log_error "Cluster-admin privileges required."
		exit 1
	fi
	log_debug "Cluster-admin privileges confirmed"
}

# Wait for a resource to be ready
# Usage: wait_for_resource <type/name> <namespace> <timeout>
wait_for_resource() {
	local resource="$1"
	local namespace="${2:-default}"
	local timeout="${3:-300s}"

	log_info "Waiting for $resource to be ready..."
	if oc wait --for=condition=available --timeout="$timeout" "$resource" -n "$namespace"; then
		log_success "$resource is ready"
		return 0
	else
		log_error "$resource failed to become ready within $timeout"
		return 1
	fi
}
