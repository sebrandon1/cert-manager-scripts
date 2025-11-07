# cert-manager-scripts

Scripts for testing and managing cert-manager-operator on OpenShift clusters with local ACME testing using Pebble.

## Quick Start

Test DNS-01 certificate issuance in 3 commands:

```bash
make install-cert-manager-operator  # Install cert-manager-operator
make quick-test                     # Setup Pebble, fake DNS, and test wildcard cert
make clean                          # Clean up when done
```

The `quick-test` target installs Pebble ACME server (air-gapped), fake DNS server, configures DNS forwarding, creates a DNS-01 ClusterIssuer, and requests a wildcard certificate (`*.example.com`).

**Note:** Check certificate progress with `make verify-cert` if needed.

## Prerequisites

- OpenShift cluster (4.20+)
- `oc` CLI and cluster-admin privileges
- `envsubst` command: `brew install gettext` (macOS) or `dnf install gettext` (RHEL/Fedora)

## What is Pebble?

Pebble is a small ACME test server from Let's Encrypt that runs locally in your cluster. Test cert-manager without rate limits, public DNS, or internet connectivity. See [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) for details.

## Getting Started

**Complete Setup (One Command)**
```bash
make test-all
```

**Step-by-Step**
```bash
make install-cert-manager-operator  # Install operator
make install-pebble                 # Install Pebble ACME server
make create-issuer                  # Create ClusterIssuer
make create-certs                   # Create test certificates
```

**Verify Installation**
```bash
oc get pods -n cert-manager-operator
oc get pods -n cert-manager
oc get pods -n pebble
oc get clusterissuer
oc get certificate -A
```

See [INSTALLATION.md](./INSTALLATION.md) for detailed instructions.

## Available Make Targets

Run `make help` to see all available targets. Key targets include:

- `make quick-http-test` / `make quick-dns-test` - Complete end-to-end tests
- `make check-network` - Check cluster network configuration
- `make install-all` - Install cert-manager-operator and Pebble
- `make create-issuer` / `make create-dns01-issuer` - Create ClusterIssuers
- `make test-cert` / `make verify-cert` - Test and verify certificates
- `make clean` - Clean up all resources (keeps operator)

## Documentation

- [INSTALLATION.md](./INSTALLATION.md) - Detailed installation instructions
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions
- [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) - Pebble usage guide
- [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md) - IPv4/IPv6/dual-stack testing
- [DNS01-SETUP.md](./DNS01-SETUP.md) - DNS-01 challenge setup
- [CONTRIBUTING.md](./CONTRIBUTING.md) - CI/CD and contributing guidelines

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common problems and solutions.

Quick debug commands:
```bash
oc logs -n cert-manager deployment/cert-manager --tail=50
oc get certificate -A
oc describe certificate <cert-name> -n <namespace>
oc get challenge -A
```

## Contributing

Contributions welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, code style requirements, CI/CD pipeline details, and pull request process.

## License

Apache 2.0
