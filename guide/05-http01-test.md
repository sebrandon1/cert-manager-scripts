# HTTP-01 Certificate Test

Let's create a test certificate using HTTP-01 validation to verify everything works.

## Step 1: Create Test Certificates

Run the certificate creation:

```bash
make create-certs
```

This creates test certificates in the `default` namespace.

## Step 2: Watch Certificate Creation

Monitor the certificate status:

```bash
oc get certificate -n default -w
```

Press `Ctrl+C` to stop watching once the certificate shows `READY: True`.

## Step 3: Check Certificate Details

View detailed certificate information:

```bash
oc describe certificate -n default
```

Look for the `Status` section showing successful issuance.

## Step 4: Verify the Secret

The certificate is stored as a Kubernetes secret:

```bash
oc get secret -n default | grep test-certificate
```

## Step 5: Inspect Certificate Content (Optional)

First, find your certificate secret name:

```bash
oc get secret -n default | grep tls
```

Then view the actual certificate (replace `<secret-name>` with your secret name from above):

```bash
oc get secret <secret-name> -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

Example with the test-cert-http01 certificate:

```bash
oc get secret test-cert-http01-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Troubleshooting

If the certificate doesn't become ready, use the automated diagnostic script:

```bash
./scripts/troubleshooting/diagnose-http01.sh
```

Or check manually:

```bash
oc describe certificaterequest -n default
oc describe order -n default
oc describe challenge -n default
```

### Common Issues

- **Certificate stays in "Not Ready" status** - See [Certificate Not Ready](08-troubleshooting.md#certificate-not-ready)
- **HTTP-01 challenge failures** - See [HTTP-01 Challenge Failures](08-troubleshooting.md#http-01-challenge-failures)
- **"Account does not exist" errors** - See [ACME Account Does Not Exist Error](08-troubleshooting.md#acme-account-does-not-exist-error) (common after Pebble restarts)

For comprehensive troubleshooting, see the [full Troubleshooting Guide](08-troubleshooting.md).

## What's Next?

Great! HTTP-01 validation is working. Now let's set up DNS-01 validation for wildcard certificates.

---

**[← Previous: HTTP-01 Setup](04-http01-setup.md)** | **[Next Step: DNS-01 Setup →](06-dns01-setup.md)**

