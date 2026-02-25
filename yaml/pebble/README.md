# Pebble

Let's Encrypt Pebble ACME test server. A lightweight ACME server that runs in your cluster for testing cert-manager without rate limits or public DNS requirements.

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace for Pebble deployment |
| `configmap.yaml` | Pebble configuration (ports, validation settings) |
| `deployment.yaml` | Deploys letsencrypt/pebble container |
| `service.yaml` | Exposes ACME API (14000) and management (15000) |
| `route.yaml` | Optional route for external access |

## Usage

```bash
# Deploy Pebble
make install-pebble

# Or manually:
export PEBBLE_NAMESPACE="pebble"
export DNS_SERVER="8.8.8.8:53"
export PEBBLE_ALWAYS_VALID="0"

envsubst < yaml/pebble/namespace.yaml | oc apply -f -
envsubst < yaml/pebble/configmap.yaml | oc apply -f -
envsubst < yaml/pebble/deployment.yaml | oc apply -f -
envsubst < yaml/pebble/service.yaml | oc apply -f -
envsubst < yaml/pebble/route.yaml | oc apply -f -
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PEBBLE_NAMESPACE` | `pebble` | Namespace for Pebble |
| `DNS_SERVER` | `8.8.8.8:53` | DNS server for challenge validation |
| `PEBBLE_ALWAYS_VALID` | `0` | Auto-validate challenges (1=yes, 0=no) |

## What is Pebble?

Pebble is a small ACME test server from Let's Encrypt that:
- Has no rate limits (unlike production Let's Encrypt)
- Runs entirely in your OpenShift cluster
- Can auto-validate challenges for easier testing
- Issues real X.509 certificates (self-signed CA)

## Accessing Pebble

| Access | URL |
|--------|-----|
| Internal | `https://pebble.pebble.svc.cluster.local:14000/dir` |
| External | Through OpenShift route (if created) |

Use the internal URL when configuring cert-manager ClusterIssuers.

## Configuration

Key `configmap.yaml` settings:
- **listenAddress**: ACME API endpoint (port 14000)
- **managementListenAddress**: Management API (port 15000)
- **httpPort/tlsPort**: Ports for HTTP-01 challenge validation

## Related Documentation

- [PEBBLE-USAGE.md](../../PEBBLE-USAGE.md) - Detailed Pebble usage guide
