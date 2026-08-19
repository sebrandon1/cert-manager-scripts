# Pebble Challenge Test Server

Mock DNS/HTTP server for ACME challenge testing. Companion service to Pebble that provides configurable responses for HTTP-01, TLS-ALPN-01, and DNS-01 challenges.

## Files

| File | Description |
|------|-------------|
| `deployment.yaml` | Deploys letsencrypt/pebble-challtestsrv container |
| `service.yaml` | Exposes DNS (8053), HTTP (5002), and management (8055) |

## Usage

```bash
# Deploy alongside Pebble (separate target — not part of make install-pebble)
make install-pebble-challtestsrv

# Or apply manifests directly:
export PEBBLE_NAMESPACE="pebble"
envsubst < yaml/pebble-challtestsrv/deployment.yaml | oc apply -f -
envsubst < yaml/pebble-challtestsrv/service.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `PEBBLE_NAMESPACE` | Namespace (typically same as Pebble) |

## Ports

| Port | Protocol | Purpose | Exposed by Service |
|------|----------|---------|--------------------|
| 8053 | UDP/TCP | DNS queries | yes |
| 8055 | TCP | Management API | yes |
| 5002 | TCP | HTTP-01 challenge responses | container only |
| 5001 | TCP | TLS-ALPN-01/HTTPS challenges | container only |

## Management API

The challenge test server provides an API (port 8055) to:
- Add/remove mock DNS records
- Configure HTTP-01 challenge responses
- Set default IP addresses for challenge validation

## When to Use

Use pebble-challtestsrv when you need fine-grained control over challenge responses. For simple testing, `PEBBLE_ALWAYS_VALID=1` is often sufficient.

## Related Documentation

- [Pebble Usage](../../docs/pebble-usage.md) - Pebble usage guide
