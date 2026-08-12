# Documentation

## Guides

| Document | Description |
|----------|-------------|
| [Getting Started](getting-started.md) | Step-by-step walkthrough from prerequisites to testing |
| [Installation](installation.md) | Detailed installation for each component |
| [Pebble Usage](pebble-usage.md) | Working with the local ACME test server |
| [DNS-01 Setup](dns01-setup.md) | Air-gapped DNS-01 challenge configuration |
| [Network Support](network-support.md) | IPv4/IPv6/dual-stack cluster testing |
| [IBU Testing](ibu-testing.md) | Image-Based Upgrade certificate validation |
| [Troubleshooting](troubleshooting.md) | Common issues and diagnostic commands |

## Reference

| Document | Description |
|----------|-------------|
| [IBU-FAQ](IBU-FAQ.md) | Frequently asked questions about IBU certificate testing |
| [CRC Cluster Health](CRC-CLUSTER-HEALTH-IMPROVEMENTS.md) | CI workflow health check enhancements |
| [Contributing](../CONTRIBUTING.md) | Development setup and pull request process |

## Choosing a Challenge Type

| | HTTP-01 | DNS-01 |
|---|---------|--------|
| **Best for** | Standard, single-domain certificates | Wildcard certificates (`*.example.com`) |
| **Setup complexity** | Low — just needs an accessible ingress/route | Medium — requires DNS server configuration |
| **Air-gapped support** | Yes (with Pebble inside the cluster) | Yes (with fake-dns-api) |
| **Wildcard support** | No | Yes |
| **Quick test command** | `make quick-http-test` | `make quick-dns-test` |

**Start with HTTP-01** if you just need to verify cert-manager is working. **Use DNS-01** if you need wildcard certificates or want to test DNS-based validation flows.

See the [Getting Started](getting-started.md) guide for a hands-on walkthrough of both methods.
