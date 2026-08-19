# DNS-01 Challenge Setup Guide

DNS-01 is required for wildcard certificates (`*.example.com`). This repo supports two fully local paths:

| Path | Use when |
|------|----------|
| **fake DNS** (recommended) | Air-gapped / CI testing. RFC2136 nameserver inside the cluster. |
| **acme-dns** | You want a closer ACME-DNS workflow. cert-manager uses the native `acmeDNS` solver. |

Neither path needs a public DNS provider or internet connectivity.

## Recommended: fake DNS

```bash
make install-cert-manager-operator
make install-fake-dns
DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 make install-pebble
make create-dns01-issuer
make test-cert
make verify-cert
```

Or run the whole flow with `make quick-dns-test`.

`create-dns01-issuer` applies `yaml/issuers/pebble-dns01-simple-clusterissuer.yaml` (RFC2136 pointing at `DNS_SERVER`). For smoke tests, install Pebble with `PEBBLE_ALWAYS_VALID=1` so challenges succeed without a real TXT lookup.

See [Fake DNS API](../yaml/fake-dns-api/README.md) for manifests.

## Alternative: acme-dns

[acme-dns](https://github.com/acme-dns/acme-dns) exposes DNS (port 53) and an HTTP API (port 8080). cert-manager talks to it with the native [`acmeDNS` solver](https://cert-manager.io/docs/configuration/acme/dns01/acme-dns/) — no webhook install is required.

```bash
make install-local-dns
DNS_SERVER=acme-dns.acme-dns.svc.cluster.local:53 PEBBLE_ALWAYS_VALID=1 make install-pebble
make register-acmedns
```

`register-acmedns` registers an account and creates a credentials Secret in the `cert-manager` namespace. Point a ClusterIssuer at that secret:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: pebble-dns01-issuer
spec:
  acme:
    server: https://pebble.pebble.svc.cluster.local:14000/dir
    skipTLSVerify: true
    email: test@example.com
    privateKeySecretRef:
      name: pebble-dns01-account-key
    solvers:
    - dns01:
        acmeDNS:
          host: http://acme-dns.acme-dns.svc.cluster.local:8080
          accountSecretRef:
            name: acme-dns-credentials
            key: acmedns.json
```

Then:

```bash
make test-cert
make verify-cert
```

### acme-dns troubleshooting

```bash
oc logs -n acme-dns deployment/acme-dns
oc describe pod -n acme-dns

# DNS resolution from the Pebble namespace
oc run --rm -i dns-test --image=busybox --restart=Never -n pebble -- \
  nslookup acme-dns.acme-dns.svc.cluster.local

oc describe challenge -n default
oc logs -n cert-manager deployment/cert-manager -f
```

## How validation works

1. cert-manager requests a certificate from Pebble.
2. Pebble asks for a DNS-01 proof (TXT record).
3. cert-manager publishes the TXT record via fake DNS (RFC2136) or the acme-dns API.
4. Pebble queries that local DNS server.
5. With `PEBBLE_ALWAYS_VALID=1`, Pebble accepts the challenge without checking DNS.
6. Pebble issues the certificate and cert-manager stores it in a Secret.

## References

- [acme-dns](https://github.com/acme-dns/acme-dns)
- [cert-manager ACMEDNS solver](https://cert-manager.io/docs/configuration/acme/dns01/acme-dns/)
- [cert-manager DNS-01 Guide](https://cert-manager.io/docs/configuration/acme/dns01/)
- [Pebble](https://github.com/letsencrypt/pebble)
