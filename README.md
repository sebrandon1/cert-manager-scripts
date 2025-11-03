# cert-manager-scripts

A collection of scripts for testing and managing cert-manager-operator on OpenShift clusters.

## Overview

This repository contains bash and Python scripts for:
- Installing and configuring cert-manager-operator
- Testing certificate issuance scenarios (wildcard, apiServer, application certs)
- Verifying DNS-01 and HTTP-01 challenges
- Testing IPv4, IPv6, and dual-stack configurations
- Setting up local ACME testing environments

## Prerequisites

- OpenShift cluster (4.20+ recommended)
- `oc` CLI installed and configured
- `envsubst` command (part of gettext package)
  - macOS: `brew install gettext`
  - RHEL/Fedora: `dnf install gettext`
- Cluster-admin privileges
- Bash shell (for shell scripts)

## Repository Structure

```
cert-manager-scripts/
├── Makefile                           # Make targets for common tasks
├── README.md                          # This file
├── install-cert-manager-operator.sh   # Installation script
└── yaml/                              # YAML manifests organized by purpose
    └── cert-manager-operator/
        ├── operatorgroup.yaml         # OperatorGroup definition
        └── subscription.yaml          # Subscription definition
```

## Scripts

### Installation

#### `install-cert-manager-operator.sh`

Installs the cert-manager Operator for Red Hat OpenShift following the official documentation.

**Usage:**
```bash
# Using the script directly
./install-cert-manager-operator.sh

# Or using Make
make install-cert-manager-operator
```

**What it does:**
- Checks prerequisites (oc CLI, envsubst, cluster login, admin privileges)
- Creates the `cert-manager-operator` namespace
- Applies OperatorGroup and Subscription resources from YAML templates
- Uses `envsubst` for variable substitution in YAML files
- Waits for operator to be ready
- Verifies the installation
- Displays next steps
- **Idempotent**: Safe to run multiple times

**Reference:** [Red Hat OpenShift cert-manager Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)

## Getting Started

1. Clone this repository:
   ```bash
   git clone <repo-url>
   cd cert-manager-scripts
   ```

2. Log in to your OpenShift cluster:
   ```bash
   oc login <cluster-url>
   ```

3. Install cert-manager-operator:
   ```bash
   make install-cert-manager-operator
   ```
   
   Or run the script directly:
   ```bash
   ./install-cert-manager-operator.sh
   ```

4. Verify the installation:
   ```bash
   oc get pods -n cert-manager-operator
   oc get pods -n cert-manager
   ```

## Makefile Targets

Run `make help` to see all available targets:

```bash
make help
```

Available targets:
- `make install-cert-manager-operator` - Install cert-manager Operator
- `make uninstall-cert-manager-operator` - Uninstall cert-manager Operator (coming soon)
- `make clean` - Clean up temporary files
- `make help` - Show help message

## Next Steps

After installing cert-manager-operator, you can:
- Configure issuers (ACME, CA, self-signed)
- Create certificate resources
- Secure routes with cert-manager
- Set up DNS-01 challenges for wildcard certificates

## Contributing

This is a collection of testing and utility scripts. Feel free to add new scripts or improve existing ones.

## License

Apache 2.0
