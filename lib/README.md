# Library

Shared shell library functions for cert-manager-scripts.

## Files

| File | Description |
|------|-------------|
| `common.sh` | Core library with logging, validation, and utility functions |

## Usage

Source `common.sh` at the top of your scripts:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
```

## Available Functions

### Logging

| Function | Description |
|----------|-------------|
| `log_error "msg"` | Red error message (stderr) |
| `log_warn "msg"` | Yellow warning message |
| `log_info "msg"` | Blue informational message |
| `log_success "msg"` | Green success message |
| `log_debug "msg"` | Bold debug message (when LOG_LEVEL=debug) |

### Dependency Checking

| Function | Description |
|----------|-------------|
| `require_cmd oc yq jq` | Verify required commands exist |
| `require_cluster` | Verify OpenShift cluster connectivity |
| `require_cluster_admin` | Verify cluster-admin privileges |

### Environment

| Function | Description |
|----------|-------------|
| `load_env [path]` | Load .env file (searches script dir) |

### Cleanup

| Function | Description |
|----------|-------------|
| `setup_cleanup` | Set up EXIT trap with timing |
| `register_temp_file /path` | Register file for cleanup on exit |

### Utilities

| Function | Description |
|----------|-------------|
| `retry 3 5 cmd args...` | Retry command with exponential backoff |
| `wait_for_resource type/name ns timeout` | Wait for resource readiness |
| `print_summary "Key" "Val" ...` | Print formatted summary table |

## Log Levels

Set via `LOG_LEVEL` environment variable:

| Level | Value | Output |
|-------|-------|--------|
| quiet | 0 | Nothing |
| error | 1 | Errors only |
| warn | 2 | Errors + warnings |
| info | 3 | Errors + warnings + info (default) |
| debug | 4 | Everything |

Example:
```bash
LOG_LEVEL=debug ./scripts/install-pebble.sh
```

## Example Script

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

setup_cleanup
load_env
require_cmd oc envsubst
require_cluster

log_info "Starting deployment..."
# ... your code ...
log_success "Deployment complete"

print_summary "Namespace" "$NAMESPACE" "Status" "Ready"
```
