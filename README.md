# cert-manager-scripts

Scripts for testing and managing cert-manager-operator on OpenShift clusters with local ACME testing using Pebble.

## Quick Start

Test certificate issuance in 3 commands:

```bash
make install-cert-manager-operator  # Install cert-manager-operator
make quick-http-test                # Setup Pebble (ALWAYS_VALID=1) + HTTP-01 cert
make clean                          # Clean up when done
```

The `quick-http-test` target installs Pebble ACME server with auto-validation, creates an HTTP-01 ClusterIssuer, and requests a test certificate. For DNS-01 with air-gapped fake DNS, use `make quick-dns-test` instead.

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
- `make check-network-stack` - Detect IPv4/IPv6/dual-stack cluster configuration
- `make check-workload-partitioning` - Verify cert-manager pods are not using workload partitioning
- `make install-all` - Install cert-manager-operator and Pebble
- `make create-issuer` / `make create-dns01-issuer` - Create ClusterIssuers
- `make create-certs` - Create test certificates (HTTP-01)
- `make create-apiserver-cert` - Create API server certificate
- `make verify-apiserver-cert` - Verify API server certificate doesn't break cluster access
- `make test-cert` / `make verify-cert` - Test and verify certificates
- `make clean` - Clean up all resources (keeps operator)

### IBU Testing

Test certificate behavior during Image-Based Upgrade (IBU) simulation:

```bash
make quick-ibu-test    # End-to-end IBU certificate loss validation
make clean-ibu         # Clean up IBU test resources
```

See [IBU-TESTING.md](./IBU-TESTING.md) for details on validating cert-manager behavior during IBU.

## Documentation

- [INSTALLATION.md](./INSTALLATION.md) - Detailed installation instructions
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions
- [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) - Pebble usage guide
- [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md) - IPv4/IPv6/dual-stack testing
- [DNS01-SETUP.md](./DNS01-SETUP.md) - DNS-01 challenge setup
- [IBU-TESTING.md](./IBU-TESTING.md) - Image-Based Upgrade certificate loss validation
- [CONTRIBUTING.md](./CONTRIBUTING.md) - CI/CD and contributing guidelines

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common problems and solutions.

### Automated Diagnostics

```bash
# Run all checks
make troubleshoot

# Check certificates
./scripts/troubleshooting/check-certificate.sh

# Check ClusterIssuers
./scripts/troubleshooting/check-issuer.sh

# Check workload partitioning (SNO/compact clusters)
make check-workload-partitioning
```

### Quick Debug Commands

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
