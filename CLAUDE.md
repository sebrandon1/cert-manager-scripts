# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automation toolkit for testing cert-manager-operator on OpenShift clusters using Pebble (a local ACME test server from Let's Encrypt). Supports both HTTP-01 and DNS-01 challenge types, air-gapped environments, and IBU (Image-Based Upgrade) certificate validation. Runs entirely within the cluster without requiring public DNS or internet connectivity.

## Commands

### Linting & Validation
```bash
make lint          # Run shellcheck + shfmt on all scripts (CI gate)
make test-unit     # Run BATS unit tests (no cluster)
make preflight     # Check all tool dependencies and cluster prerequisites
```

### Quick End-to-End Tests
```bash
make quick-http-test       # Install operator + Pebble (ALWAYS_VALID=1) + HTTP-01 cert
make quick-dns-test        # Install fake DNS + Pebble + DNS-01 wildcard cert
make quick-multi-algo-test # Install operator + create ECDSA/RSA/Ed25519 certs + verify PEM formats
```

### Step-by-Step Workflow
```bash
make install-cert-manager-operator
make install-pebble
make install-fake-dns       # For air-gapped DNS-01
make create-issuer          # HTTP-01 ClusterIssuer
make create-dns01-issuer    # DNS-01 ClusterIssuer
make test-cert              # Create wildcard cert
make verify-cert            # Check cert status
```

### Troubleshooting
```bash
make troubleshoot                          # Run all diagnostics
make check-cert CERT=name NS=namespace     # Debug specific certificate
make check-issuer ISSUER=name              # Debug specific ClusterIssuer
make diagnose-http01                       # HTTP-01 challenge issues
make diagnose-dns01                        # DNS-01 challenge issues
```

### IBU Testing
```bash
make install-ibu-prereqs   # Install MinIO + OADP
make test-ibu-certs        # Scenario 1: certificate loss (default IBU)
make test-ibu-preserved    # Scenario 2: certificate preservation (LCA labels)
make test-ibu-both         # Run both scenarios
make quick-ibu-test        # End-to-end IBU test
make create-multi-algo-certs  # Create certs with all key algorithms (ECDSA, RSA, Ed25519)
make verify-key-formats       # Verify PEM key formats of TLS secrets
make test-ibu-multi-algo      # IBU cert loss test with all key algorithms
```

### Cleanup
```bash
make clean         # Remove certs, issuers, Pebble, fake DNS (keeps operator)
make clean-ibu     # Remove IBU resources (MinIO, OADP, backups)
make clean-multi-algo-certs            # Remove multi-algorithm test certs
make uninstall-cert-manager-operator   # Remove operator (interactive confirm)
```

### Fix Formatting
```bash
make fmt    # Auto-fix shell formatting (shfmt -w scripts/ lib/)
```

## Architecture

### Execution Flow
```
Makefile targets → scripts/*.sh → lib/common.sh (shared utilities)
                                → yaml/ templates (envsubst substitution)
                                → oc apply to cluster
```

All YAML manifests use `${VARIABLE}` placeholders processed by `envsubst` at apply time. Variables are exported in scripts with defaults: `export VAR="${VAR:-default}"`.

### Script Categories

- **`scripts/`** — Core automation (install, create, check operations)
- **`scripts/ibu/`** — IBU testing: backup/restore simulation via OADP + MinIO (not real IBU)
- **`scripts/troubleshooting/`** — Diagnostic scripts for certs, issuers, DNS, HTTP challenges
- **`scripts/workflows/`** — CI/CD helpers (cluster access verification, recovery, validation)
- **`lib/common.sh`** — Shared library sourced by scripts

### YAML Manifests (`yaml/`)

Organized by component: `cert-manager-operator/`, `pebble/`, `fake-dns-api/`, `issuers/`, `certificates/`, `acme-dns/`, `pebble-challtestsrv/`, `ibu/` (with `minio/`, `oadp/`, `backup/` subdirs).

### Key Environment Variables

| Variable | Default | Effect |
|----------|---------|--------|
| `CERT_MANAGER_VERSION` | `v1.19.0` | Operator version pin (startingCSV in subscription) |
| `PEBBLE_ALWAYS_VALID` | `0` | Set to `1` to skip real ACME challenge validation (quick testing) |
| `DNS_SERVER` | `8.8.8.8:53` | Override for fake DNS: `fake-dns-api.fake-dns.svc.cluster.local:53` |
| `OPERATOR_NAMESPACE` | `cert-manager-operator` | Operator install namespace |
| `PEBBLE_NAMESPACE` | `pebble` | Pebble server namespace |
| `LOG_LEVEL` | `info` | `quiet\|error\|warn\|info\|debug` — controls common.sh logging |
| `DRY_RUN` | `false` | Enable dry-run mode |
| `SKIP_CONFIRM` | `0` | Set to `1` to skip interactive confirmation prompts (CI/automation) |
| `MULTI_ALGO` | `false` | Use multi-algorithm certs (ECDSA, RSA, Ed25519) in IBU tests |

### lib/common.sh API

All scripts source this library. The sourcing pattern depends on directory depth:

```bash
# scripts/*.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# scripts/ibu/*.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# scripts/troubleshooting/*.sh and scripts/workflows/*.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
```

Key functions:
- **Logging**: `log_error`, `log_warn`, `log_info`, `log_success`, `log_debug` — color-aware, respects `LOG_LEVEL`
- **Dependencies**: `require_cmd oc yq jq` — validates commands with install hints
- **Cluster**: `require_cluster` / `require_cluster_admin` — validates connectivity and privileges
- **Cluster**: `require_healthy_cluster [max_attempts] [interval]` — waits for dns, network, ingress operators to be Available
- **Environment**: `load_env` — loads `.env` from script or parent directory
- **Retry**: `retry <max_attempts> <delay> <command...>` — exponential backoff
- **Wait**: `wait_for_resource <type/name> <namespace> <timeout>` — polls until ready and logs progress every 15s
- **Cleanup**: `setup_cleanup` + `register_temp_file` — trap-based cleanup with duration tracking
- **Output**: `print_summary "Key1" "Val1" "Key2" "Val2"` — formatted summary table
- **Headers**: `print_header "Title"` — formatted section header box
- **YAML**: `apply_yaml_template <yaml_file> <resource_type>` — envsubst + oc apply with file validation
- **Namespace**: `ensure_namespace <namespace>` — idempotent namespace creation
- **Deployment**: `check_deployment_exists <deployment> <namespace>` — returns 0 if deployment is healthy
- **OLM**: `wait_for_csv <namespace> <grep_pattern> <max_attempts>` — waits for CSV to reach Succeeded phase
- **OADP**: `wait_for_backup_restore <type> <name> <namespace> <max_attempts>` — waits for backup/restore completion
- **IBU**: `build_lca_annotations <namespace>` — builds lca.openshift.io/apply-label annotation value
- **IBU**: `capture_secret_checksums <namespace> <output_file>` — captures TLS secret checksums and PEM types in a single API call
- **IBU**: `get_key_pem_type <base64_key_data>` — returns PEM header type (`EC PRIVATE KEY`, `RSA PRIVATE KEY`, `PRIVATE KEY`, or `UNKNOWN`)

## IBU Certificate Validation

Testing cert-manager behavior during OpenShift Image-Based Upgrade operations. Full report: https://gist.github.com/sebrandon1/71f33b35aea2aa4cf9edda855201c8fc

| Scenario | Behavior | Result |
|----------|----------|--------|
| **Scenario 1 (Default)** | Standard backup/restore | Certificates regenerated with new checksums — original keys lost |
| **Scenario 2 (LCA Labels)** | Resources labeled with `lca.openshift.io/apply-label` | Certificates preserved with matching checksums |

The LCA (Lifecycle Agent) apply-label format is `<apiGroup>/<version>/<resourceType>/<namespace>/<resourceName>`. This ensures resources are included in backups via labelSelector, retaining raw certificate data during restore.

**Preserve certificates** when long-lived, shared with external systems, or where regeneration causes issues. **Allow regeneration** for short-lived, auto-renewed certificates.

## Code Style

- All scripts use `set -euo pipefail`
- All scripts source `lib/common.sh` — do not redefine color constants, logging functions, or utility helpers inline
- Scripts resolve their own location with `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (varies by depth — see sourcing patterns above)
- Use shared functions: `require_cmd`/`require_cluster` instead of inline prerequisite checks, `apply_yaml_template` instead of inline envsubst, `print_header` instead of inline echo headers, `wait_for_resource` instead of custom polling loops
- `shfmt` formatting: 2-space indentation (tabs in Makefile), binary operators at line start, switch cases indented
- `shellcheck` with severity=error. Local `make lint` also excludes SC1091, SC2034, SC2329
- Cleanup operations use `--ignore-not-found=true` for idempotency
- New Makefile targets need a `## Description` comment suffix for `make help` integration

## CI Pipeline

CI runs on PRs to main (`.github/workflows/pre-main.yml`):
1. **shell-format-check** — `shfmt -d scripts/ lib/`
2. **shellcheck** — severity=error on `scripts/` and `lib/`
3. **workload-partitioning-check** — script exists, is executable, syntax + Makefile/docs mentions
4. **verify-structure** — directory layout, key files, script references
5. **version-query-check** — version query scripts for pebble, acme-dns, operator, minio, ubi9-python
6. **unit-tests** — BATS (`make test-unit`), no cluster
7. **kind-integration-test** — Kind cluster, cert-manager v1.19.0 / v1.20.0
8. **integration-test** — OCP 4.20/4.21/4.22 × cert-manager v1.19.0/v1.20.0 CRC matrix (skipped for dependabot); `make quick-http-test`, API server cert, workload partitioning, network stack detection

## Requirements

- OpenShift cluster (4.20+) with `oc` CLI and cluster-admin privileges
- `envsubst` (`brew install gettext` on macOS)
- `shellcheck` and `shfmt` for linting (`brew install shellcheck shfmt` on macOS)
