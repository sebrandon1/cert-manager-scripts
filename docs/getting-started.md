# Getting Started

Step-by-step walkthrough from prerequisites to testing certificates with both HTTP-01 and DNS-01 validation.

## Prerequisites

Before you begin, ensure you have:

- OpenShift cluster (4.20+)
- `oc` CLI installed and configured with cluster-admin privileges
- `openssl` for certificate inspection
- `jq` (`brew install jq` or `dnf install jq`)
- `envsubst` (`brew install gettext` on macOS, `dnf install gettext` on RHEL/Fedora)

Verify cluster access:

```bash
oc cluster-info
```

Check network configuration:

```bash
make check-network
```

Optionally copy the environment template to customize defaults:

```bash
cp .env.example .env
```

## Step 1: Install cert-manager Operator

```bash
make install-cert-manager-operator
```

Wait for the operator to be ready:

```bash
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/openshift-cert-manager-operator.cert-manager-operator -n cert-manager-operator --timeout=300s
```

Verify cert-manager pods are running:

```bash
oc get pods -n cert-manager
```

You should see `cert-manager`, `cert-manager-webhook`, and `cert-manager-cainjector` pods in `Running` status.

## Step 2: Install Pebble ACME Server

Pebble is a lightweight ACME test server from Let's Encrypt, perfect for testing cert-manager without rate limits.

```bash
make install-pebble
```

Verify Pebble pods are ready:

```bash
oc get pods -n pebble
```

## Choose Your Path

At this point, choose a validation method based on your needs:

| Need | Method | Next Step |
|------|--------|-----------|
| Standard certificates (simplest setup) | HTTP-01 | [Step 3a](#step-3a-http-01-certificates) |
| Wildcard certificates (`*.example.com`) | DNS-01 | [Step 3b](#step-3b-dns-01-wildcard-certificates) |
| Quick smoke test (skip real validation) | Either + `PEBBLE_ALWAYS_VALID=1` | `make quick-http-test` or `make quick-dns-test` |

For more detail on choosing between HTTP-01 and DNS-01, see the [challenge type comparison](README.md#choosing-a-challenge-type).

## Step 3a: HTTP-01 Certificates

### Create the HTTP-01 Issuer

```bash
make create-issuer
```

Verify the ClusterIssuer is ready:

```bash
oc get clusterissuer pebble-issuer
```

### Create Test Certificates

```bash
make create-certs
```

Monitor certificate status:

```bash
oc get certificate -n default -w
```

Press `Ctrl+C` once the certificate shows `READY: True`.

### Inspect the Certificate

```bash
oc get secret test-cert-simple-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Step 3b: DNS-01 Wildcard Certificates

DNS-01 is required for wildcard certificates and uses a fake DNS API for air-gapped testing.

### Install DNS-01 Test Environment

```bash
make install-fake-dns
```

Reinstall Pebble with DNS-01 support and create the issuer:

```bash
DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 make install-pebble
make create-dns01-issuer
```

Verify the DNS-01 issuer is ready:

```bash
oc get clusterissuer pebble-dns01-issuer
```

### Create a Wildcard Certificate

```bash
make test-cert
```

Verify the certificate:

```bash
make verify-cert
```

Inspect the Subject Alternative Names:

```bash
oc get secret wildcard-test-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Subject Alternative Name"
```

## Troubleshooting

If certificates aren't becoming ready, use the automated diagnostic scripts:

```bash
make troubleshoot                  # Run all diagnostics
make diagnose-http01               # HTTP-01 specific issues
make diagnose-dns01                # DNS-01 specific issues
make check-cert CERT=name NS=ns   # Debug a specific certificate
```

See the full [Troubleshooting Guide](troubleshooting.md) for common issues and solutions.

## Cleanup

```bash
make clean                          # Remove certs, issuers, Pebble, fake DNS (keeps operator)
make uninstall-cert-manager-operator  # Remove operator (interactive confirm)
```

## Next Steps

- [Pebble Usage](pebble-usage.md) - Advanced Pebble configuration and management API
- [DNS-01 Setup](dns01-setup.md) - In-depth DNS-01 configuration
- [Network Support](network-support.md) - IPv4/IPv6/dual-stack testing
- [IBU Testing](ibu-testing.md) - Image-Based Upgrade certificate validation
