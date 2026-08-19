# ACME-DNS

ACME-DNS server for DNS-01 challenge automation. Provides a specialized DNS server that handles TXT record management for ACME certificate issuance.

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace for ACME-DNS deployment |
| `configmap.yaml` | ACME-DNS configuration (domain, API settings) |
| `deployment.yaml` | Deploys joohoi/acme-dns container |
| `service.yaml` | Exposes DNS (53) and API (8080) ports |

## Usage

```bash
# Deploy ACME-DNS
make install-local-dns

# Register an account and create the credentials Secret
make register-acmedns

# Or apply manifests directly:
export ACMEDNS_NAMESPACE="acme-dns"
envsubst < yaml/acme-dns/namespace.yaml | oc apply -f -
envsubst < yaml/acme-dns/configmap.yaml | oc apply -f -
envsubst < yaml/acme-dns/deployment.yaml | oc apply -f -
envsubst < yaml/acme-dns/service.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `ACMEDNS_NAMESPACE` | Namespace for ACME-DNS deployment |

## How It Works

ACME-DNS stores TXT records in sqlite3 and exposes both DNS (port 53) and HTTP API (port 8080) interfaces. cert-manager uses the native `acmeDNS` solver against that API (`make register-acmedns`).

## Related Documentation

- [DNS-01 Setup](../../docs/dns01-setup.md) - DNS-01 challenge configuration
