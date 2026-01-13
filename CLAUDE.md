# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Scripts for testing and managing cert-manager-operator on OpenShift clusters with local ACME testing using Pebble. Provides a complete workflow for testing certificate issuance without requiring public DNS or internet connectivity.

## Common Commands

### Quick Start
```bash
make install-cert-manager-operator  # Install cert-manager-operator
make quick-test                     # Setup Pebble, fake DNS, and test wildcard cert
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
make request-cert
```

## Architecture

- **`scripts/`** - Main automation scripts
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
| `TROUBLESHOOTING.md` | Common issues and solutions |
| `CONTRIBUTING.md` | Contribution guidelines |

## What is Pebble?

Pebble is a small ACME test server from Let's Encrypt that runs locally in your cluster. Test cert-manager without rate limits, public DNS, or internet connectivity.

## Requirements

- OpenShift cluster (4.20+)
- `oc` CLI with cluster-admin privileges
- `envsubst` command (`brew install gettext` on macOS)

## Code Style

### Bash
- Use `shellcheck` for linting
- Follow Makefile conventions for targets
- Include helpful comments and usage information
