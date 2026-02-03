# Pebble Challenge Test Server

Mock DNS/HTTP server for ACME challenge testing. Companion service to Pebble that provides configurable responses for HTTP-01, TLS-ALPN-01, and DNS-01 challenges.

## Files

| File | Description |
|------|-------------|
| `deployment.yaml` | Deploys letsencrypt/pebble-challtestsrv container |
| `service.yaml` | Exposes DNS (8053), HTTP (5002), and management (8055) |

## Usage

```bash
# Deploy alongside Pebble
export PEBBLE_NAMESPACE="pebble"
envsubst < yaml/pebble-challtestsrv/deployment.yaml | oc apply -f -
envsubst < yaml/pebble-challtestsrv/service.yaml | oc apply -f -
```

## Variables

| Variable | Description |
|----------|-------------|
| `PEBBLE_NAMESPACE` | Namespace (typically same as Pebble) |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8053 | UDP/TCP | DNS queries |
| 5002 | TCP | HTTP-01 challenge responses |
| 5001 | TCP | TLS-ALPN-01/HTTPS challenges |
| 8055 | TCP | Management API |

## Management API

The challenge test server provides an API (port 8055) to:
- Add/remove mock DNS records
- Configure HTTP-01 challenge responses
- Set default IP addresses for challenge validation

## When to Use

Use pebble-challtestsrv when you need fine-grained control over challenge responses. For simple testing, Pebble's `ALWAYS_VALID=1` mode is often sufficient.

## Related Documentation

- [PEBBLE-USAGE.md](../../PEBBLE-USAGE.md) - Pebble usage guide
