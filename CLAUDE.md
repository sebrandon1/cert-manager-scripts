# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Scripts for testing and managing cert-manager-operator on OpenShift clusters with local ACME testing using Pebble. Provides a complete workflow for testing certificate issuance without requiring public DNS or internet connectivity.

## Common Commands

### Quick Start
```bash
make install-cert-manager-operator  # Install cert-manager-operator
make quick-dns-test                 # Setup Pebble, fake DNS, and test wildcard cert
make clean                          # Clean up when done
```

### Verification
```bash
make verify-cert  # Check certificate progress
```

### Individual Steps
```bash
make install-pebble
make install-fake-dns
make create-issuer
make test-cert
```

### IBU Testing
```bash
make install-ibu-prereqs  # Install MinIO + OADP
make test-ibu-certs       # Run IBU certificate loss simulation
make quick-ibu-test       # End-to-end IBU test
make clean-ibu            # Clean up IBU resources
```

### Linting
```bash
make lint      # Run shellcheck and shfmt on all scripts
make preflight # Check all dependencies and prerequisites
```

## Architecture

- **`scripts/`** - Main automation scripts
  - **`scripts/ibu/`** - IBU (Image-Based Upgrade) testing scripts
  - **`scripts/troubleshooting/`** - Diagnostic and troubleshooting scripts
  - **`scripts/workflows/`** - Workflow automation helpers
- **`lib/`** - Shared shell library functions (common.sh)
- **`yaml/`** - Kubernetes/OpenShift manifests
- **`guide/`** - Step-by-step guides
- **`docs/`** - Additional documentation

## Key Documentation

| File | Description |
|------|-------------|
| `INSTALLATION.md` | Cert-manager installation guide |
| `DNS01-SETUP.md` | DNS-01 challenge configuration |
| `PEBBLE-USAGE.md` | Using Pebble for local ACME testing |
| `NETWORK-SUPPORT.md` | Network configuration details |
| `IBU-TESTING.md` | IBU certificate loss validation |
| `TROUBLESHOOTING.md` | Common issues and solutions |
| `CONTRIBUTING.md` | Contribution guidelines |
| `.env.example` | Environment variable examples |

## What is Pebble?

Pebble is a small ACME test server from Let's Encrypt that runs locally in your cluster. Test cert-manager without rate limits, public DNS, or internet connectivity.

## Requirements

- OpenShift cluster (4.20+)
- `oc` CLI with cluster-admin privileges
- `envsubst` command (`brew install gettext` on macOS)
- `shellcheck` for linting (`brew install shellcheck` on macOS)
- `shfmt` for shell formatting (`brew install shfmt` on macOS)

## IBU Certificate Validation Report

Validation testing for cert-manager certificate behavior during OpenShift Image-Based Upgrade (IBU) operations. Full report: https://gist.github.com/sebrandon1/71f33b35aea2aa4cf9edda855201c8fc

### Key Findings

| Scenario | Behavior | Result |
|----------|----------|--------|
| **Scenario 1 (Default)** | Standard backup/restore | Certificates regenerated with new checksums - original keys lost |
| **Scenario 2 (LCA Labels)** | Resources labeled with `lca.openshift.io/apply-label` | Certificates preserved with matching checksums |

### LCA Apply-Label Mechanism

Format: `<apiGroup>/<version>/<resourceType>/<namespace>/<resourceName>`

The Lifecycle Agent applies `lca.openshift.io/backup` labels to specified resources, which are then included in the backup using a labelSelector, ensuring raw certificate data is retained during restore.

### Recommendations

- **Preserve certificates** when they're long-lived, shared with external systems, or where regeneration causes operational issues
- **Allow regeneration** for short-lived, auto-renewed certificates during IBU

## Code Style

### Bash
- Use `shellcheck` for linting
- Use `shfmt` for consistent formatting
- Follow Makefile conventions for targets
- Include helpful comments and usage information
- Source shared functions from `lib/common.sh` when appropriate
