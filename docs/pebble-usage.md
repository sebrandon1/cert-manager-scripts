# Pebble ACME Test Server - Usage Guide

This guide explains how to use Pebble with cert-manager for local testing.

## What is Pebble?

Pebble is a lightweight ACME test server created by Let's Encrypt specifically for testing ACME clients like cert-manager. It's designed to mimic Let's Encrypt's behavior without the complexity or rate limits of a production server.

## Installation

```bash
# Basic installation
make install-pebble

# Installation with auto-validation enabled
PEBBLE_ALWAYS_VALID=1 make install-pebble

# Custom namespace
PEBBLE_NAMESPACE=acme-test make install-pebble
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PEBBLE_NAMESPACE` | `pebble` | Kubernetes namespace for Pebble |
| `DNS_SERVER` | `8.8.8.8:53` | DNS server for ACME validation |
| `PEBBLE_ALWAYS_VALID` | `0` | Auto-validate all challenges (1=yes, 0=no) |

### PEBBLE_ALWAYS_VALID Explained

**When set to `1` (enabled):**
- All ACME challenges automatically succeed
- No need for proper DNS records or HTTP routes
- Perfect for initial testing and development
- Doesn't validate your actual challenge setup

**When set to `0` (disabled - default):**
- Challenges must be properly configured
- DNS records must resolve correctly
- HTTP-01 routes must be accessible
- Tests your real ACME infrastructure

## Creating a ClusterIssuer for Pebble

### Basic HTTP-01 Issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: pebble-issuer
spec:
  acme:
    # Pebble's ACME directory URL
    server: https://pebble.pebble.svc.cluster.local:14000/dir
    
    # Skip TLS verification (Pebble uses self-signed certs)
    skipTLSVerify: true
    
    # Private key for ACME account
    privateKeySecretRef:
      name: pebble-account-key
    
    # HTTP-01 challenge solver
    solvers:
    - http01:
        ingress:
          class: openshift-default
```

### DNS-01 Issuer (requires DNS provider)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: pebble-dns01-issuer
spec:
  acme:
    server: https://pebble.pebble.svc.cluster.local:14000/dir
    skipTLSVerify: true
    privateKeySecretRef:
      name: pebble-dns01-account-key
    solvers:
    - dns01:
        rfc2136:
          nameserver: fake-dns-api.fake-dns.svc.cluster.local:53
          tsigKeyName: dummy-key
          tsigAlgorithm: HMACSHA256
          tsigSecretSecretRef:
            name: rfc2136-credentials
            key: tsig-secret
```

Prefer `make create-dns01-issuer` over applying this by hand. See [DNS-01 Setup](dns01-setup.md).

## Testing Certificate Issuance

### Simple Test Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: default
spec:
  secretName: test-tls
  issuerRef:
    name: pebble-issuer
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
```

### Wildcard Certificate (requires DNS-01)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-certificate
  namespace: default
spec:
  secretName: wildcard-tls
  issuerRef:
    name: pebble-dns01-issuer
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.example.com"
```

## Troubleshooting

### Check Pebble Status

```bash
# Check if Pebble is running
oc get pods -n pebble

# View Pebble logs
oc logs -n pebble deployment/pebble -f

# Check Pebble service
oc get svc -n pebble
```

### Test Pebble ACME Directory

```bash
# From inside the cluster
oc run --rm -i --tty curl-test --image=curlimages/curl --restart=Never -- \
  curl -k https://pebble.pebble.svc.cluster.local:14000/dir

# Expected output: JSON with ACME directory URLs
```

Example output:
```json
{
   "keyChange": "https://pebble.pebble.svc.cluster.local:14000/rollover-account-key",
   "meta": {
      "externalAccountRequired": false,
      "termsOfService": "data:text/plain,Do%20what%20thou%20wilt"
   },
   "newAccount": "https://pebble.pebble.svc.cluster.local:14000/sign-me-up",
   "newNonce": "https://pebble.pebble.svc.cluster.local:14000/nonce-plz",
   "newOrder": "https://pebble.pebble.svc.cluster.local:14000/order-plz",
   "revokeCert": "https://pebble.pebble.svc.cluster.local:14000/revoke-cert"
}
```

### Check Certificate Status

```bash
# Check certificate status
oc get certificate -n default

# Describe certificate for details
oc describe certificate test-certificate -n default

# Check certificate request
oc get certificaterequest -n default

# Check ACME orders
oc get order -n default

# Check ACME challenges
oc get challenge -n default
```

### Getting Pebble's CA Certificate

Pebble generates its own self-signed CA certificate at startup. To get it:

```bash
# Fetch and display the CA certificate
oc run --rm -i --tty pebble-ca-fetch --image=curlimages/curl --restart=Never -- \
  curl -k https://pebble.pebble.svc.cluster.local:15000/roots/0

# Save to a file
oc run --rm -i pebble-ca-fetch --image=curlimages/curl --restart=Never -- \
  curl -k https://pebble.pebble.svc.cluster.local:15000/roots/0 > pebble-ca.crt
```

The CA certificate is available from Pebble's management API at `/roots/0`. Each time Pebble restarts, it generates a new CA certificate.

**Note**: For testing purposes, it's usually easier to use `skipTLSVerify: true` in your ClusterIssuer rather than managing the CA certificate.

### Common Issues

#### 1. Certificate Stuck in "Pending"

**Cause**: Challenge validation failing

**Solution**:
```bash
# Check challenge status
oc describe challenge -n default

# If using HTTP-01, ensure route/ingress is accessible
oc get routes -n default

# If using DNS-01, check DNS records
dig _acme-challenge.example.com
```

#### 2. "Connection Refused" to Pebble

**Cause**: Pebble not running or service misconfigured

**Solution**:
```bash
# Check Pebble pod status
oc get pods -n pebble

# Check Pebble service
oc get svc -n pebble

# Restart Pebble if needed
oc rollout restart deployment/pebble -n pebble
```

#### 3. "TLS Handshake Timeout"

**Cause**: Network policies or firewall blocking connections

**Solution**:
- Ensure cert-manager can reach Pebble service
- Check network policies in both namespaces
- Verify `skipTLSVerify: true` is set in ClusterIssuer

## Pebble Challenge Test Server (pebble-challtestsrv)

Pebble ships with a companion service called `pebble-challtestsrv` — a mock DNS/HTTP server that provides configurable responses for ACME challenge validation. Install it separately with `make install-pebble-challtestsrv` (it is **not** started by `make install-pebble`).

### When to Use challtestsrv vs PEBBLE_ALWAYS_VALID

| Approach | Use when |
|----------|----------|
| `PEBBLE_ALWAYS_VALID=1` | Quick smoke testing — all challenges auto-succeed, no DNS/HTTP setup needed |
| `pebble-challtestsrv` | You need fine-grained control over challenge responses (e.g., testing failure scenarios, specific DNS records) |

For most users, `PEBBLE_ALWAYS_VALID=1` is sufficient. Use `pebble-challtestsrv` when you want to simulate specific challenge behaviors.

### challtestsrv Ports

| Port | Protocol | Purpose | Exposed by Service |
|------|----------|---------|--------------------|
| 8053 | UDP/TCP | DNS queries | yes |
| 8055 | TCP | Management API | yes |
| 5002 | TCP | HTTP-01 challenge responses | container only |
| 5001 | TCP | TLS-ALPN-01/HTTPS challenges | container only |

### Management API

The management API on port 8055 lets you add and remove mock DNS records, configure HTTP-01 challenge responses, and set default IP addresses for challenge validation.

```bash
# Port-forward to access the management API locally
oc port-forward -n pebble svc/pebble-challtestsrv 8055:8055

# Add a mock A record
curl -s -X POST http://localhost:8055/add-a \
  -d '{"host": "example.com", "addresses": ["10.0.0.1"]}'

# Add a mock TXT record (for DNS-01 challenges)
curl -s -X POST http://localhost:8055/set-txt \
  -d '{"host": "_acme-challenge.example.com.", "value": "challenge-token-here"}'

# Set the default IPv4 address for all A record lookups
curl -s -X POST http://localhost:8055/set-default-ipv4 \
  -d '{"ip": "10.0.0.1"}'

# Clear all mock records
curl -s -X POST http://localhost:8055/clear-request-history
```

### Verifying challtestsrv is Running

```bash
oc get pods -n pebble -l app=pebble-challtestsrv
oc logs -n pebble -l app=pebble-challtestsrv
```

See the [YAML manifest documentation](../yaml/pebble-challtestsrv/README.md) for deployment details.

## Advanced Usage

### Custom DNS Server for DNS-01 Testing

If you want to test DNS-01 with a custom DNS server:

```bash
# Install Pebble with custom DNS server
DNS_SERVER=10.0.0.53:53 make install-pebble
```

### Accessing Pebble Management API

Pebble exposes a management API on port 15000:

```bash
# Port forward to access locally
oc port-forward -n pebble svc/pebble 15000:15000

# Check Pebble metrics
curl http://localhost:15000/metrics
```

### Testing Certificate Renewal

```bash
# Force immediate renewal (edit renewBefore)
oc edit certificate test-certificate -n default

# Or delete the secret to trigger re-issuance
oc delete secret test-tls -n default
```

## Integration with Scripts

### Full Testing Workflow

```bash
# 1. Install cert-manager-operator
make install-cert-manager-operator

# 2. Install Pebble with auto-validation
PEBBLE_ALWAYS_VALID=1 make install-pebble

# 3. Create ClusterIssuer
make create-issuer

# 4. Create test Certificate
oc apply -f your-test-certificate.yaml

# 5. Check status
oc get certificate -A
```

## Cleaning Up

```bash
# Delete test certificates
oc delete certificate test-certificate -n default

# Delete Pebble deployment
oc delete namespace pebble

# Delete ClusterIssuer
oc delete clusterissuer pebble-issuer
```

## References

- [Pebble GitHub Repository](https://github.com/letsencrypt/pebble)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [ACME Protocol (RFC 8555)](https://datatracker.ietf.org/doc/html/rfc8555)

