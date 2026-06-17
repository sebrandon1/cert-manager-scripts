# Documentation

Technical documentation for cert-manager-scripts beyond the main guides.

## Contents

| Document | Description |
|----------|-------------|
| [IBU-FAQ.md](IBU-FAQ.md) | Frequently asked questions about IBU certificate testing |
| [CRC-CLUSTER-HEALTH-IMPROVEMENTS.md](CRC-CLUSTER-HEALTH-IMPROVEMENTS.md) | CI workflow health check enhancements |

## IBU-FAQ.md

Answers common questions about cert-manager certificate behavior during OpenShift Image-Based Upgrade (IBU) operations:

- Does this testing address IBU certificate concerns?
- Is the cert immediately reissued or does it wait until expiration?
- What is the workflow for labeling certs?
- How does the simulation differ from real LCA behavior?

## CRC-CLUSTER-HEALTH-IMPROVEMENTS.md

Documents CI workflow improvements for CRC cluster testing:

- Enhanced cluster verification scripts
- Cluster recovery mechanisms
- Health check integration in GitHub Actions
- Troubleshooting transient failures

## Guides

| File | Description |
|------|-------------|
| [installation.md](installation.md) | Cert-manager installation guide |
| [dns01-setup.md](dns01-setup.md) | DNS-01 challenge configuration |
| [pebble-usage.md](pebble-usage.md) | Using Pebble for local ACME testing |
| [network-support.md](network-support.md) | Network configuration details |
| [ibu-testing.md](ibu-testing.md) | IBU certificate loss validation |
| [troubleshooting.md](troubleshooting.md) | Common issues and solutions |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Contribution guidelines |
