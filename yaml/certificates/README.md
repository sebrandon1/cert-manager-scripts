# Certificates

Test certificate templates for cert-manager. Used to request certificates from ClusterIssuers during testing.

## Files

| File | Description |
|------|-------------|
| `test-certificate.yaml` | Template for requesting a test certificate with 90-day validity |

## Usage

```bash
# Request a test certificate
make test-cert

# Or manually:
export CERT_NAME="test-cert"
export CERT_NAMESPACE="default"
export CERT_SECRET_NAME="test-cert-tls"
export CERT_COMMON_NAME="test.example.com"
export CERT_DNS_NAME="test.example.com"
export ISSUER_NAME="pebble-issuer"

envsubst < yaml/certificates/test-certificate.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `CERT_NAME` | Name of the Certificate resource |
| `CERT_NAMESPACE` | Namespace for the certificate |
| `CERT_SECRET_NAME` | Name of the TLS secret to create |
| `CERT_COMMON_NAME` | Certificate common name |
| `CERT_DNS_NAME` | DNS name(s) for the certificate |
| `ISSUER_NAME` | ClusterIssuer to use |

## Certificate Lifecycle

- **Duration**: 90 days (2160h)
- **Renewal**: Begins 15 days before expiry (360h)
- **Challenge**: HTTP-01 (for non-wildcard certs)

## Verification

```bash
# Check certificate status
make verify-cert

# View certificate details
oc get certificate -n $CERT_NAMESPACE $CERT_NAME -o yaml
```

## Related Documentation

- [PEBBLE-USAGE.md](../../PEBBLE-USAGE.md) - Using Pebble for testing
