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
# INTERACTIVE PROMPTS
# ============================================================================
# Prompt for confirmation, auto-accept when SKIP_CONFIRM=1 or non-interactive
# Usage: confirm "Continue anyway?" || exit 0
confirm() {
	local prompt="${1:-Continue?}"
	if [[ "${SKIP_CONFIRM:-0}" == "1" ]] || [[ ! -t 0 ]]; then
		log_debug "Auto-confirmed: $prompt (SKIP_CONFIRM=$SKIP_CONFIRM)"
		return 0
	fi
	read -p "$prompt (y/N): " -n 1 -r
	echo
	[[ $REPLY =~ ^[Yy]$ ]]
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

# Verify cert-manager is installed and webhook is ready
require_cert_manager() {
	if ! oc get deployment -n cert-manager cert-manager &>/dev/null; then
		log_error "cert-manager not found. Please install cert-manager-operator first."
		log_info "  Run: make install-cert-manager-operator"
		exit 1
	fi

	log_info "Waiting for cert-manager webhook to be ready..."
	if ! oc wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager; then
		log_error "Timeout waiting for cert-manager webhook to be ready."
		log_info "  Check webhook status: oc get deployment cert-manager-webhook -n cert-manager"
		exit 1
	fi
	log_info "cert-manager webhook is ready."
}

# Print a formatted section header
# Usage: print_header "Title"
print_header() {
	local title="${1:-Script Execution}"
	echo
	echo "========================================"
	echo "  $title"
	echo "========================================"
	echo
}

# Apply a YAML template with envsubst variable substitution
# Usage: apply_yaml_template <yaml_file> <resource_type>
apply_yaml_template() {
	local yaml_file="$1"
	local resource_type="${2:-Resource}"

	if [[ ! -f "$yaml_file" ]]; then
		log_error "YAML file not found: $yaml_file"
		return 1
	fi

	log_info "Applying $resource_type from $(basename "$yaml_file")..."
	envsubst <"$yaml_file" | oc apply -f -
}

# Create a namespace if it doesn't exist
# Usage: ensure_namespace <namespace>
ensure_namespace() {
	local namespace="$1"

	if oc get namespace "$namespace" &>/dev/null; then
		log_info "Namespace '$namespace' already exists."
	else
		log_info "Creating namespace '$namespace'..."
		oc create namespace "$namespace"
		log_info "Namespace '$namespace' created successfully."
	fi
}

# Check if a deployment exists and is healthy
# Usage: check_deployment_exists <deployment> <namespace>
# Returns 0 if deployment exists and has ready replicas
check_deployment_exists() {
	local deployment="$1"
	local namespace="$2"

	if ! oc get namespace "$namespace" &>/dev/null; then
		return 1
	fi

	if ! oc get deployment "$deployment" -n "$namespace" &>/dev/null; then
		return 1
	fi

	local ready_replicas
	ready_replicas=$(oc get deployment "$deployment" -n "$namespace" \
		-o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
	local desired_replicas
	desired_replicas=$(oc get deployment "$deployment" -n "$namespace" \
		-o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

	if [[ "$ready_replicas" = "$desired_replicas" ]] && [[ "$ready_replicas" != "0" ]]; then
		return 0
	fi

	return 1
}

# Wait for a CSV (ClusterServiceVersion) to reach Succeeded phase
# Usage: wait_for_csv <namespace> <label_or_grep_pattern> <timeout_attempts>
wait_for_csv() {
	local namespace="$1"
	local pattern="$2"
	local max_attempts="${3:-60}"

	log_info "Waiting for CSV to reach Succeeded phase..."
	local attempt=0

	while [[ $attempt -lt $max_attempts ]]; do
		if oc get csv -n "$namespace" 2>/dev/null | grep -q "${pattern}.*Succeeded"; then
			log_success "CSV is in Succeeded phase."
			return 0
		fi

		attempt=$((attempt + 1))
		if [[ $((attempt % 6)) -eq 0 ]]; then
			echo -n " [${attempt}/${max_attempts}]"
		else
			echo -n "."
		fi
		sleep 5
	done
	echo

	log_error "Timeout waiting for CSV to reach Succeeded phase."
	return 1
}

# Wait for OADP Backup or Restore to complete
# Usage: wait_for_backup_restore <type> <name> <namespace> <max_attempts>
# type: "backup" or "restore"
wait_for_backup_restore() {
	local resource_type="$1"
	local name="$2"
	local namespace="$3"
	local max_attempts="${4:-60}"

	log_info "Waiting for $resource_type to complete..."
	local attempt=0

	while [[ $attempt -lt $max_attempts ]]; do
		local phase
		phase=$(oc get "$resource_type" "$name" -n "$namespace" \
			-o jsonpath='{.status.phase}' 2>/dev/null || echo "")

		case "$phase" in
		Completed)
			log_success "${resource_type^} completed successfully!"
			return 0
			;;
		Failed | PartiallyFailed)
			log_error "${resource_type^} failed with phase: $phase"
			oc describe "$resource_type" "$name" -n "$namespace"
			return 1
			;;
		esac

		attempt=$((attempt + 1))
		if [[ $((attempt % 6)) -eq 0 ]]; then
			log_info "${resource_type^} phase: $phase ($attempt/$max_attempts)"
		fi
		sleep 5
	done

	log_error "Timeout waiting for $resource_type to complete"
	return 1
}

# Build lca.openshift.io/apply-label annotation value for cert resources
# Usage: build_lca_annotations <namespace>
build_lca_annotations() {
	local namespace="$1"
	local annotation_parts=()

	local cert_names
	cert_names=$(oc get certificates -n "$namespace" \
		-o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

	while IFS= read -r cert_name; do
		[[ -z "$cert_name" ]] && continue
		annotation_parts+=("cert-manager.io/v1/certificates/$namespace/$cert_name")

		local secret_name
		secret_name=$(oc get certificate "$cert_name" -n "$namespace" \
			-o jsonpath='{.spec.secretName}' 2>/dev/null || echo "")

		if [[ -n "$secret_name" ]]; then
			if oc get secret "$secret_name" -n "$namespace" &>/dev/null; then
				annotation_parts+=("v1/secrets/$namespace/$secret_name")
			fi
		fi
	done <<<"$cert_names"

	local annotation_value
	annotation_value=$(
		IFS=','
		echo "${annotation_parts[*]}"
	)

	echo "$annotation_value"
}

# Check IBU test prerequisites (cert-manager, OADP, MinIO)
# Usage: require_ibu_prereqs
require_ibu_prereqs() {
	require_cmd oc jq envsubst
	require_cert_manager

	if ! oc get dataprotectionapplication velero -n openshift-adp &>/dev/null; then
		log_error "OADP is not installed."
		log_info "Run 'make install-ibu-prereqs' first."
		exit 1
	fi

	if ! oc get deployment minio -n minio &>/dev/null; then
		log_error "MinIO is not installed."
		log_info "Run 'make install-minio' first."
		exit 1
	fi
}

# Extract PEM type from base64-encoded key data
# Usage: get_key_pem_type <base64_key_data>
# Returns: "EC PRIVATE KEY", "RSA PRIVATE KEY", "PRIVATE KEY", or "UNKNOWN"
get_key_pem_type() {
	local b64_data="$1"
	[[ -z "$b64_data" ]] && echo "UNKNOWN" && return

	local header
	header=$(echo "$b64_data" | base64 -d 2>/dev/null | head -1 || echo "")

	case "$header" in
	*"EC PRIVATE KEY"*) echo "EC PRIVATE KEY" ;;
	*"RSA PRIVATE KEY"*) echo "RSA PRIVATE KEY" ;;
	*"PRIVATE KEY"*) echo "PRIVATE KEY" ;;
	*) echo "UNKNOWN" ;;
	esac
}

# Capture TLS secret checksums for a namespace in a single API call
# Usage: capture_secret_checksums <namespace> <output_file>
capture_secret_checksums() {
	local namespace="$1"
	local checksums_file="$2"

	local secrets_json
	secrets_json=$(oc get secrets -n "$namespace" -o json 2>/dev/null || echo '{"items":[]}')

	echo "[]" >"$checksums_file"

	local secret_entries
	secret_entries=$(echo "$secrets_json" | jq -r '
		[.items[] | select(.type == "kubernetes.io/tls" or .data["tls.crt"] != null)]
		| .[] | [.metadata.name, (.data["tls.crt"] // ""), (.data["tls.key"] // "")] | @tsv
	')

	while IFS=$'\t' read -r name cert_data key_data; do
		[[ -z "$name" ]] && continue

		local cert_checksum=""
		if [[ -n "$cert_data" ]]; then
			cert_checksum=$(echo "$cert_data" | shasum -a 256 | cut -d' ' -f1)
		fi

		local key_checksum=""
		local pem_type="UNKNOWN"
		if [[ -n "$key_data" ]]; then
			key_checksum=$(echo "$key_data" | shasum -a 256 | cut -d' ' -f1)
			pem_type=$(get_key_pem_type "$key_data")
		fi

		jq --arg name "$name" \
			--arg cert_checksum "$cert_checksum" \
			--arg key_checksum "$key_checksum" \
			--arg pem_type "$pem_type" \
			'. += [{name: $name, cert_checksum: $cert_checksum, key_checksum: $key_checksum, pem_type: $pem_type}]' \
			"$checksums_file" >"$checksums_file.tmp" && mv "$checksums_file.tmp" "$checksums_file"
	done <<<"$secret_entries"
}
