# Troubleshooting Guide

Common issues and solutions when working with cert-manager and Pebble.

## Quick Diagnostics

We provide automated troubleshooting scripts to quickly diagnose issues:

```bash
# Run all diagnostics
./scripts/troubleshooting/check-all.sh

# Check all certificates
./scripts/troubleshooting/check-certificate.sh

# Check specific certificate
./scripts/troubleshooting/check-certificate.sh <cert-name> <namespace>

# Check all ClusterIssuers
./scripts/troubleshooting/check-issuer.sh

# Check specific ClusterIssuer
./scripts/troubleshooting/check-issuer.sh <issuer-name>

# Diagnose HTTP-01 issues
./scripts/troubleshooting/diagnose-http01.sh

# Diagnose DNS-01 issues
./scripts/troubleshooting/diagnose-dns01.sh

# Check workload partitioning configuration
./scripts/troubleshooting/check-workload-partitioning.sh
```

## Certificate Not Ready

If your certificate stays in `Ready: False` status:

### Check Certificate Details

Use the automated script to check all certificates:

```bash
./scripts/troubleshooting/check-certificate.sh
```

Or check a specific certificate:

```bash
./scripts/troubleshooting/check-certificate.sh <certificate-name> <namespace>
```

Or manually:

```bash
oc describe certificate <certificate-name> -n <namespace>
```

Look for error messages in the `Status` and `Events` sections.

### Check Certificate Request

```bash
oc get certificaterequest -n <namespace>
oc describe certificaterequest <request-name> -n <namespace>
```

### Check Order Status

```bash
oc get order -n <namespace>
oc describe order <order-name> -n <namespace>
```

### Check Challenge Status

```bash
oc get challenge -n <namespace>
oc describe challenge <challenge-name> -n <namespace>
```

## HTTP-01 Challenge Failures

### Run HTTP-01 Diagnostics

Use the automated diagnostic script:

```bash
./scripts/troubleshooting/diagnose-http01.sh
```

This will check:
- cert-manager status
- Pebble connectivity
- HTTP-01 issuers
- Active challenges
- Recent logs

### Verify Issuer Configuration

```bash
./scripts/troubleshooting/check-issuer.sh pebble-issuer
```

Or manually:

```bash
oc get clusterissuer pebble-issuer -o yaml
```

Ensure the ACME server URL points to your Pebble route.

### Check Pebble Logs

```bash
oc logs -n pebble -l app=pebble
```

Look for incoming challenge requests and any validation errors.

### Verify Network Connectivity

```bash
make check-network
```

## DNS-01 Challenge Failures

### Run DNS-01 Diagnostics

Use the automated diagnostic script:

```bash
./scripts/troubleshooting/diagnose-dns01.sh
```

This will check:
- cert-manager and Pebble status
- Fake DNS API
- Challenge test server
- DNS-01 issuers
- Active challenges
- Recent logs

### Check Fake DNS API Service

```bash
oc get pods -n fake-dns
oc logs -n fake-dns -l app=fake-dns-api
```

### Verify DNS-01 Issuer

```bash
./scripts/troubleshooting/check-issuer.sh pebble-dns01-issuer
```

Or manually:

```bash
oc get clusterissuer pebble-dns01-issuer -o yaml
```

### Check Challenge Test Server

```bash
oc get pods -n pebble -l app=pebble-challtestsrv
oc logs -n pebble -l app=pebble-challtestsrv
```

## cert-manager Webhook Issues

If you see webhook connection errors:

### Check Webhook Pod

```bash
oc get pods -n cert-manager | grep webhook
oc logs -n cert-manager -l app=webhook
```

### Verify Webhook Service

```bash
oc get svc -n cert-manager cert-manager-webhook
```

## Issuer Not Ready

### Check Issuer Status

Use the automated script to check all issuers:

```bash
./scripts/troubleshooting/check-issuer.sh
```

Or check a specific issuer:

```bash
./scripts/troubleshooting/check-issuer.sh <issuer-name>
```

Or manually:

```bash
oc describe clusterissuer <issuer-name>
```

### Verify ACME Account Registration

Look for ACME account URL in the issuer status. If missing, the issuer couldn't register with Pebble.

### Test Pebble Connectivity

```bash
PEBBLE_URL=$(oc get route -n pebble pebble -o jsonpath='{.spec.host}')
curl -k https://${PEBBLE_URL}/dir
```

You should see the ACME directory endpoints.

## ACME Account Does Not Exist Error

If you see errors like `accountDoesNotExist: Account https://pebble.pebble.svc.cluster.local:14000/my-account/X not found`, this happens when Pebble restarts and loses its ephemeral ACME account data.

**This is normal and expected behavior with Pebble** - it doesn't persist account data between restarts.

### When This Happens

- Pebble pod restarts or crashes
- You reinstall Pebble
- Your cluster restarts
- Testing after a long break

### Quick Fix

Delete the cached ACME account secrets and let cert-manager re-register:

```bash
# Delete ACME account secrets
oc delete secret pebble-issuer-account-key pebble-dns01-issuer-account-key -n cert-manager

# Delete any stuck certificate requests
oc delete certificaterequest -n <namespace> --all

# Optional: Delete and recreate stuck certificates
oc delete certificate <cert-name> -n <namespace>
oc apply -f yaml/certificates/test-certificate.yaml
```

### Verify Fix

Check that the ClusterIssuer has a new account registered:

```bash
oc describe clusterissuer pebble-issuer | grep -A 5 "Status:"
```

You should see a new `Uri` with a fresh account ID.

## Workload Partitioning Issues

If you're deploying cert-manager on Single Node OpenShift (SNO) or compact clusters with workload partitioning enabled, verify that cert-manager pods are NOT configured with workload partitioning annotations.

### Check Workload Partitioning Configuration

```bash
./scripts/troubleshooting/check-workload-partitioning.sh
# or
make check-workload-partitioning
```

### Why This Matters

Workload partitioning isolates management workloads in SNO/compact clusters. cert-manager should NOT use workload partitioning because:
- cert-manager needs to run on all node types
- Restricting to management CPU sets can cause performance issues
- cert-manager webhook needs to be accessible cluster-wide

### Symptoms

- cert-manager webhook timeouts
- Slow certificate issuance
- Pods scheduled only on specific nodes

### Fix

If workload partitioning is incorrectly configured:

1. Remove annotations from CertManager CR
2. Remove annotations from cert-manager namespace
3. Restart cert-manager pods

See the [workload partitioning check script](../scripts/troubleshooting/check-workload-partitioning.sh) for detailed recommendations.

## General Debugging Tips

### View cert-manager Controller Logs

```bash
oc logs -n cert-manager -l app=cert-manager
```

### View All cert-manager Resources

```bash
oc get certificate,certificaterequest,order,challenge -A
```

### Increase Logging Verbosity

Edit the cert-manager deployment to add `--v=4` flag for more detailed logs.

## Need More Help?

For detailed documentation, refer to:
- [Troubleshooting](../docs/troubleshooting.md) - Extended troubleshooting guide
- [DNS-01 Setup](../docs/dns01-setup.md) - Detailed DNS-01 configuration
- [Pebble Usage](../docs/pebble-usage.md) - Pebble-specific information
- [Network Support](../docs/network-support.md) - Network configuration details

## Clean Up

To remove all test resources:

```bash
# Clean certificates only
make clean-certs

# Clean everything (keeps cert-manager-operator)
make clean

# Uninstall cert-manager operator (use with caution)
make uninstall-cert-manager-operator
```

---

**[← Previous: DNS-01 Test](07-dns01-test.md)** | **[Back to Prerequisites](01-prerequisites.md)**

