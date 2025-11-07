# DNS-01 Certificate Test

Let's create a wildcard certificate using DNS-01 validation.

## Step 1: Create a Wildcard Certificate

Create a wildcard certificate:

```bash
make test-cert
```

This creates a certificate for `*.example.com` and `example.com`.

## Step 2: Verify Certificate Status

Check the certificate status and details:

```bash
make verify-cert
```

This will show:
- Certificate status
- Orders and challenges
- Whether the certificate is ready
- Helpful commands if troubleshooting is needed

## Step 3: Monitor Certificate Creation (Optional)

To watch the certificate status in real-time:

```bash
oc get certificate wildcard-test -n default -w
```

DNS-01 validation may take a bit longer than HTTP-01. Press `Ctrl+C` when ready.

## Step 4: Inspect Certificate Details

View the issued certificate details:

```bash
oc get secret wildcard-test-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Subject Alternative Name"
```

You should see both `*.example.com` and `example.com` in the Subject Alternative Names.

## Troubleshooting

If the certificate fails, use the automated diagnostic script:

```bash
./scripts/troubleshooting/diagnose-dns01.sh
```

Or check manually:

```bash
# Check the order status
oc describe order -n default

# Check challenge details
oc get challenge -n default
oc describe challenge -n default

# Check fake DNS API logs
oc logs -n fake-dns -l app=fake-dns-api

# Check Pebble logs
oc logs -n pebble -l app=pebble
```

### Common Issues

- **Certificate stays in "Not Ready" status** - See [Certificate Not Ready](08-troubleshooting.md#certificate-not-ready)
- **DNS-01 challenge failures** - See [DNS-01 Challenge Failures](08-troubleshooting.md#dns-01-challenge-failures)
- **"Account does not exist" errors** - See [ACME Account Does Not Exist Error](08-troubleshooting.md#acme-account-does-not-exist-error) (common after Pebble restarts)

For comprehensive troubleshooting, see the [full Troubleshooting Guide](08-troubleshooting.md).

## What's Next?

Congratulations! You've successfully tested both HTTP-01 and DNS-01 validation methods. Check out the troubleshooting guide for common issues.

---

**[← Previous: DNS-01 Setup](06-dns01-setup.md)** | **[Next Step: Troubleshooting →](08-troubleshooting.md)**

