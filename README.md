# cert-manager-scripts

Automation toolkit for testing cert-manager-operator on OpenShift clusters using
Pebble, a local ACME test server from Let's Encrypt. Supports HTTP-01 and DNS-01
challenges, air-gapped environments, and IBU certificate validation — all without
requiring public DNS or internet connectivity.

## Quick Start

```bash
make install-cert-manager-operator  # Install cert-manager-operator
make quick-http-test                # Pebble + HTTP-01 cert (auto-validated)
make clean                          # Clean up when done
```

For DNS-01 with air-gapped fake DNS, use `make quick-dns-test` instead.

## Key Features

- **HTTP-01 & DNS-01 Challenges** — Full ACME flow with Pebble inside the cluster
- **Air-Gapped DNS** — Fake DNS server for DNS-01 testing without external dependencies
- **IBU Certificate Validation** — Test cert-manager behavior during Image-Based Upgrade operations
- **IPv4/IPv6/Dual-Stack** — Automatic network stack detection and configuration
- **API Server Certificates** — Create and verify certificates for the OpenShift API server
- **Automated Diagnostics** — Troubleshoot certs, issuers, DNS, and HTTP challenges

## Guides

See [docs/README.md](docs/README.md) for the full index.

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Walkthrough from prerequisites to HTTP-01 and DNS-01 tests |
| [Installation](docs/installation.md) | Component-by-component install |
| [Pebble Usage](docs/pebble-usage.md) | Local ACME test server |
| [DNS-01 Setup](docs/dns01-setup.md) | Air-gapped DNS-01 (fake DNS or acme-dns) |
| [Network Support](docs/network-support.md) | IPv4/IPv6/dual-stack |
| [IBU Testing](docs/ibu-testing.md) | Image-Based Upgrade certificate validation |
| [Troubleshooting](docs/troubleshooting.md) | Diagnostics and common failures |
| [Contributing](CONTRIBUTING.md) | Development setup and pull request process |

## Prerequisites

- OpenShift cluster (4.20+)
- `oc` CLI with cluster-admin privileges
- `openssl`: certificate inspection (pre-installed on most systems)
- `jq`: `brew install jq` (macOS) or `dnf install jq` (RHEL/Fedora)
- `envsubst`: `brew install gettext` (macOS) or `dnf install gettext` (RHEL/Fedora)

Optionally copy the environment template to customize defaults:

```bash
cp .env.example .env
```

## Development

```bash
make help       # Show all available targets
make preflight  # Check tool dependencies and cluster prerequisites
make lint       # Run shellcheck + shfmt (CI gate)
make fmt        # Auto-fix shell formatting
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
