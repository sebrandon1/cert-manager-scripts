# cert-manager-scripts

A collection of scripts for testing and managing cert-manager-operator on OpenShift clusters.

## Overview

This repository contains bash scripts for:
- Installing and configuring cert-manager-operator
- Testing certificate issuance scenarios (wildcard, apiServer, application certs)
- Verifying DNS-01 and HTTP-01 challenges
- Testing IPv4, IPv6, and dual-stack configurations
- Setting up local ACME testing environments

## Quick Start (3 Commands!)

Want to quickly test DNS-01 certificate issuance? Just run these 3 commands:

```bash
# 1. Install cert-manager-operator (if not already installed)
make install-cert-manager-operator

# 2. Run the quick test (sets up everything and tests)
make quick-test

# 3. Clean up when done
make clean
```

That's it! The `quick-test` target will:
- Install Pebble ACME server (air-gapped)
- Install fake DNS server (for DNS-01 challenges)
- Configure DNS forwarding
- Create a DNS-01 ClusterIssuer
- Request a wildcard certificate (`*.example.com`)
- Verify the certificate status

**Note:** If the certificate isn't ready after the test completes, check progress with:
```bash
make verify-cert
```

## Repository Structure

```
cert-manager-scripts/
├── scripts/                            # Shell scripts
│   ├── check-cluster-network.sh        # Check IPv4/IPv6/dual-stack support
│   ├── install-cert-manager-operator.sh # Install cert-manager-operator
│   ├── install-pebble.sh               # Install Pebble ACME server
│   ├── install-fake-dns.sh             # Install fake DNS for testing
│   ├── create-issuer.sh                # Create ClusterIssuer (HTTP-01)
│   ├── create-dns01-issuer.sh          # Create ClusterIssuer (DNS-01)
│   └── create-test-certificates.sh     # Create test certificates
├── yaml/                               # YAML manifests organized by purpose
│   ├── cert-manager-operator/          # Operator installation
│   ├── pebble/                         # Pebble ACME server
│   ├── fake-dns-api/                   # Fake DNS for air-gapped testing
│   ├── issuers/                        # ClusterIssuer templates
│   └── certificates/                   # Certificate templates
├── Makefile                            # Make targets for common tasks
├── README.md                           # This file
├── INSTALLATION.md                     # Detailed installation guide
├── TROUBLESHOOTING.md                  # Common issues and solutions
├── CONTRIBUTING.md                     # CI/CD and contributing guide
├── PEBBLE-USAGE.md                     # Detailed Pebble usage guide
├── NETWORK-SUPPORT.md                  # IPv4/IPv6/dual-stack guide
└── DNS01-SETUP.md                      # DNS-01 challenge setup
```

## Prerequisites

- OpenShift cluster (4.20+ recommended)
- `oc` CLI installed and configured
- `envsubst` command (part of gettext package)
  - macOS: `brew install gettext`
  - RHEL/Fedora: `dnf install gettext`
- Cluster-admin privileges
- Bash shell

## What is Pebble?

**Pebble** is a small ACME test server developed by the Let's Encrypt team. It mimics the behavior of Let's Encrypt's production ACME server but runs locally in your cluster. This is perfect for testing cert-manager without:
- Hitting Let's Encrypt rate limits
- Needing real public DNS records
- Requiring internet connectivity
- Dealing with production certificate concerns

**Key Benefits:**
- **No rate limits** - test as much as you want
- **Fast** - instant certificate issuance
- **Local** - runs entirely in your OpenShift cluster
- **Safe** - doesn't issue real certificates
- **Configurable** - can be set to auto-validate challenges for testing

See [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) for detailed usage guide and examples.

## Getting Started

### Step 1: Check Your Cluster (Recommended)

Check your cluster's network configuration to understand IPv4, IPv6, or dual-stack support:

```bash
make check-network
```

See [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md) for more information.

### Step 2: Install Components

Choose one of the following approaches:

**Option A: Complete Setup (One Command)**
```bash
make test-all
```

**Option B: Step-by-Step**
```bash
make install-cert-manager-operator  # Install operator
make install-pebble                 # Install Pebble ACME server
make create-issuer                  # Create ClusterIssuer
make create-certs                   # Create test certificates
```

See [INSTALLATION.md](./INSTALLATION.md) for detailed installation instructions.

### Step 3: Verify Installation

```bash
# Check installations
oc get pods -n cert-manager-operator
oc get pods -n cert-manager
oc get pods -n pebble

# Check cert-manager resources
oc get clusterissuer
oc get certificate -A
```

## Available Make Targets

Run `make help` to see all available targets:

### Development
- `make lint` - Check shell script formatting with shfmt

### Quick Testing
- `make quick-http-test` - Complete end-to-end HTTP-01 test (CI workflow)
- `make quick-dns-test` - Complete end-to-end DNS-01 test (air-gapped)
- `make test-cert` - Create a test wildcard certificate
- `make verify-cert` - Check certificate status

### Installation
- `make check-network` - Check cluster network configuration
- `make install-cert-manager-operator` - Install cert-manager Operator
- `make install-pebble` - Install Pebble ACME test server
- `make install-fake-dns` - Install fake DNS for air-gapped testing
- `make install-all` - Install cert-manager-operator and Pebble
- `make test-all` - Complete setup: install + configure + test
- `make test-dns01` - Complete DNS-01 setup (air-gapped)

### Configuration
- `make create-issuer` - Create ClusterIssuer (HTTP-01)
- `make create-dns01-issuer` - Create ClusterIssuer (DNS-01)
- `make create-certs` - Create test certificates

### Cleanup
- `make clean` - Clean up all resources (keeps operator)
- `make clean-certs` - Clean up certificates only
- `make clean-pebble` - Clean up Pebble only
- `make clean-fake-dns` - Clean up fake DNS only
- `make clean-issuers` - Clean up ClusterIssuers only
- `make uninstall-cert-manager-operator` - Uninstall operator (WARNING!)

## Documentation

- **[INSTALLATION.md](./INSTALLATION.md)** - Detailed installation instructions for all components
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues, debug commands, and solutions
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - CI/CD information and contributing guidelines
- **[PEBBLE-USAGE.md](./PEBBLE-USAGE.md)** - Detailed Pebble usage guide with examples
- **[NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md)** - IPv4, IPv6, and dual-stack testing guide
- **[DNS01-SETUP.md](./DNS01-SETUP.md)** - DNS-01 challenge configuration and testing

## Troubleshooting

Having issues? Check the [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) guide for common problems and solutions.

**Quick debug commands:**
```bash
# Check cert-manager logs
oc logs -n cert-manager deployment/cert-manager --tail=50

# Check certificate status
oc get certificate -A
oc describe certificate <cert-name> -n <namespace>

# Check challenges
oc get challenge -A
oc describe challenge <challenge-name> -n <namespace>

# Check Pebble logs
oc logs -n pebble deployment/pebble --tail=50
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for:
- Development setup
- Code style and formatting requirements
- CI/CD pipeline details
- Pull request process

## Continuous Integration

This repository uses GitHub Actions to automatically test all changes:
- **Shell Format Check** - Validates formatting with `shfmt`
- **Integration Test** - Deploys OCP 4.19 and validates HTTP-01 certificate issuance

See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.

## License

Apache 2.0
