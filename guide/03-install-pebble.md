# Install Pebble ACME Server

Pebble is a small ACME test server that mimics Let's Encrypt, perfect for testing cert-manager without rate limits.

## Step 1: Install Pebble

Run the Pebble installation:

```bash
make install-pebble
```

This will:
- Create the `pebble` namespace
- Deploy Pebble server with configuration
- Deploy the challenge test server for DNS-01 validation
- Set up the service and route

## Step 2: Verify Pebble is Running

Check that Pebble pods are ready:

```bash
oc get pods -n pebble
```

You should see:
- `pebble-*` pod in `Running` status
- `pebble-challtestsrv-*` pod in `Running` status

## Step 3: Get Pebble Route

Find your Pebble ACME server URL:

```bash
oc get route -n pebble pebble -o jsonpath='{.spec.host}'
```

Save this URL - you'll need it when creating issuers.

## What's Next?

With Pebble running, we can now create an HTTP-01 issuer to start issuing certificates.

---

**[← Previous: Install cert-manager](02-install-cert-manager.md)** | **[Next Step: HTTP-01 Setup →](04-http01-setup.md)**

