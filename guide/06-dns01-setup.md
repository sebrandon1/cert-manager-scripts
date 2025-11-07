# DNS-01 Challenge Setup

DNS-01 validation is required for wildcard certificates. We'll use acme-dns for simplified DNS management.

## Step 1: Install DNS-01 Test Environment

Run the complete DNS-01 setup:

```bash
make test-dns01
```

This will:
- Install the fake DNS API server (for air-gapped testing)
- Reinstall Pebble with DNS-01 support
- Create the DNS-01 ClusterIssuer

## Step 2: Verify Components are Running

Check that all pods are ready:

```bash
# Check fake DNS API
oc get pods -n fake-dns

# Check Pebble
oc get pods -n pebble
```

All pods should be in `Running` status.

## Step 3: Verify DNS-01 Issuer

Check that the issuer is ready:

```bash
oc get clusterissuer pebble-dns01-issuer
```

Status should show `READY: True`.

## How DNS-01 Works

DNS-01 validation:
1. ✅ cert-manager requests a certificate from Pebble
2. ✅ Pebble provides a DNS challenge token
3. ✅ cert-manager creates a TXT record via the fake DNS API
4. ✅ Pebble validates by querying the DNS record
5. ✅ Certificate is issued upon successful validation

**Note:** This setup uses a fake DNS API for air-gapped testing. The `PEBBLE_ALWAYS_VALID=1` flag tells Pebble to accept all DNS challenges.

## What's Next?

Now let's test creating wildcard certificates using DNS-01 validation.

---

**[← Previous: HTTP-01 Test](05-http01-test.md)** | **[Next Step: DNS-01 Test →](07-dns01-test.md)**

