# Fake DNS API

Air-gapped DNS testing server for cert-manager DNS-01 challenges. Accepts RFC2136 DNS updates and responds to SOA/TXT queries without requiring external DNS infrastructure.

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace for the fake DNS server |
| `configmap.yaml` | Python DNS API server script |
| `deployment.yaml` | Deploys the DNS server on UBI9 Python |
| `service.yaml` | Exposes DNS (53) and health check (8080) ports |
| `serviceaccount.yaml` | ServiceAccount for the deployment |

## Usage

```bash
# Deploy fake DNS API
make install-fake-dns

# Or manually:
export FAKEDNS_NAMESPACE="fake-dns"
envsubst < yaml/fake-dns-api/namespace.yaml | oc apply -f -
envsubst < yaml/fake-dns-api/configmap.yaml | oc apply -f -
envsubst < yaml/fake-dns-api/serviceaccount.yaml | oc apply -f -
envsubst < yaml/fake-dns-api/deployment.yaml | oc apply -f -
envsubst < yaml/fake-dns-api/service.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `FAKEDNS_NAMESPACE` | Namespace for fake DNS deployment |

## How It Works

The fake DNS API server:
1. Listens on port 53 for DNS queries (SOA, TXT)
2. Accepts RFC2136 dynamic DNS UPDATE requests
3. Stores TXT records in memory
4. Returns stored records when queried

This enables testing DNS-01 challenges without public DNS or internet connectivity.

## Use Case

Combined with Pebble's `ALWAYS_VALID=1` mode, the fake DNS server allows complete air-gapped testing of cert-manager DNS-01 workflows.

## Related Documentation

- [DNS01-SETUP.md](../../DNS01-SETUP.md) - DNS-01 challenge configuration
- [NETWORK-SUPPORT.md](../../NETWORK-SUPPORT.md) - Air-gapped setup
