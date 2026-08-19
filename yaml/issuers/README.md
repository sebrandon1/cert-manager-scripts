# Issuers

ClusterIssuer configurations for cert-manager. These define how certificates are requested from ACME servers (Pebble for testing).

## Files

| File | Description |
|------|-------------|
| `pebble-clusterissuer.yaml` | HTTP-01 challenge issuer using ingress |
| `pebble-dns01-clusterissuer.yaml` | DNS-01 issuer with webhook solver placeholder |
| `pebble-dns01-simple-clusterissuer.yaml` | DNS-01 issuer using RFC2136 (used by `make create-dns01-issuer`) |
| `selfsigned-clusterissuer.yaml` | Self-signed issuer for the root CA |
| `root-ca-certificate.yaml` | Self-signed root CA certificate |
| `ca-clusterissuer.yaml` | CA issuer that signs with the root CA |

## Usage

```bash
# Create an issuer
make create-issuer

# Or manually (HTTP-01):
export ISSUER_NAME="pebble-issuer"
export ACME_SERVER_URL="https://pebble.pebble.svc.cluster.local:14000/dir"
export ACME_EMAIL="test@example.com"
export INGRESS_CLASS="openshift-default"

envsubst < yaml/issuers/pebble-clusterissuer.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `ISSUER_NAME` | Name of the ClusterIssuer |
| `ACME_SERVER_URL` | ACME directory URL (Pebble endpoint) |
| `ACME_EMAIL` | Email for ACME account registration |
| `INGRESS_CLASS` | Ingress class for HTTP-01 challenges |
| `DNS_SERVER` | DNS server for RFC2136 (DNS-01 only) |

## Issuer Types

### HTTP-01 (`pebble-clusterissuer.yaml`)
- Uses ingress-based challenge solving
- Works for non-wildcard certificates
- Requires accessible ingress routes

### DNS-01 Webhook (`pebble-dns01-clusterissuer.yaml`)
- Placeholder for webhook-based DNS solvers
- Use with `PEBBLE_ALWAYS_VALID=1`

### DNS-01 RFC2136 (`pebble-dns01-simple-clusterissuer.yaml`)
- Uses RFC2136 dynamic DNS updates
- Works with fake-dns-api for air-gapped testing
- Required for wildcard certificates

## Choosing an Issuer

| Certificate Type | Recommended Issuer |
|-----------------|-------------------|
| Non-wildcard | HTTP-01 (`pebble-clusterissuer.yaml`) |
| Wildcard (`*.example.com`) | DNS-01 (`pebble-dns01-simple-clusterissuer.yaml`) |
| Air-gapped testing | DNS-01 with `PEBBLE_ALWAYS_VALID=1` |

## Related Documentation

- [DNS-01 Setup](../../docs/dns01-setup.md) - DNS-01 configuration
- [Pebble Usage](../../docs/pebble-usage.md) - Pebble usage guide
