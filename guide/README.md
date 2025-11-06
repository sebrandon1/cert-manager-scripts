# cert-manager Step-by-Step Guide

Welcome! This guide will walk you through setting up and testing cert-manager with Pebble ACME server on OpenShift.

## 📚 Guide Structure

Follow these guides in order for a complete setup:

### Getting Started
1. **[Prerequisites](01-prerequisites.md)** - Requirements and cluster setup

### Installation
2. **[Install cert-manager](02-install-cert-manager.md)** - Deploy cert-manager operator
3. **[Install Pebble](03-install-pebble.md)** - Set up Pebble ACME server

### HTTP-01 Validation (Simple)
4. **[HTTP-01 Setup](04-http01-setup.md)** - Create HTTP-01 issuer
5. **[HTTP-01 Test](05-http01-test.md)** - Test certificate creation

### DNS-01 Validation (Wildcard Certificates)
6. **[DNS-01 Setup](06-dns01-setup.md)** - Configure DNS-01 with acme-dns
7. **[DNS-01 Test](07-dns01-test.md)** - Test wildcard certificates

### Help
8. **[Troubleshooting](08-troubleshooting.md)** - Common issues and solutions

## 🚀 Quick Start

If you want to get up and running quickly:

```bash
# Complete HTTP-01 test (installs everything + creates test certificates)
make test-all

# Verify certificates
oc get certificate -A
```

Or for DNS-01/wildcard certificates:

```bash
# Complete DNS-01 setup
make test-dns01

# Create and verify wildcard certificate
make test-cert
make verify-cert
```

## 📖 About This Guide

- **Short & Sweet** - Each guide is concise and actionable
- **Copy-Paste Ready** - All commands are ready to run
- **Step Navigation** - Easy links to move between steps
- **Two Validation Methods** - Learn both HTTP-01 and DNS-01

## 🎯 Choose Your Path

**Just need basic certificates?** Follow guides 1-5 for HTTP-01 validation.

**Need wildcard certificates?** Complete the full guide (1-8) including DNS-01 setup.

**Having issues?** Jump straight to the [Troubleshooting Guide](08-troubleshooting.md).

## 📚 Additional Resources

- [Main README](../README.md) - Project overview
- [Installation Guide](../INSTALLATION.md) - Detailed installation instructions
- [DNS-01 Setup](../DNS01-SETUP.md) - In-depth DNS-01 configuration
- [Pebble Usage](../PEBBLE-USAGE.md) - Working with Pebble
- [Network Support](../NETWORK-SUPPORT.md) - Network configuration
- [Contributing](../CONTRIBUTING.md) - How to contribute

---

**Ready to start?** [Begin with Prerequisites →](01-prerequisites.md)

