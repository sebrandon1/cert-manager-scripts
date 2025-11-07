# HTTP-01 Challenge Setup

Create a ClusterIssuer that uses HTTP-01 validation. This is the simplest method for certificate validation.

## Step 1: Create HTTP-01 Issuer

Run the issuer creation:

```bash
make create-issuer
```

This creates a ClusterIssuer named `pebble-issuer` that uses HTTP-01 challenges.

## Step 2: Verify the Issuer

Check that the ClusterIssuer is ready:

```bash
oc get clusterissuer pebble-issuer
```

You should see `READY` status as `True`.

## Step 3: View Issuer Details (Optional)

To see the full configuration:

```bash
oc describe clusterissuer pebble-issuer
```

## How HTTP-01 Works

The HTTP-01 challenge works by:
1. ✅ cert-manager requests a certificate from Pebble
2. ✅ Pebble responds with a challenge token
3. ✅ cert-manager creates a temporary HTTP endpoint with the token
4. ✅ Pebble validates by fetching the token via HTTP
5. ✅ Certificate is issued upon successful validation

## What's Next?

Now let's test certificate creation using the HTTP-01 issuer.

---

**[← Previous: Install Pebble](03-install-pebble.md)** | **[Next Step: HTTP-01 Test →](05-http01-test.md)**

