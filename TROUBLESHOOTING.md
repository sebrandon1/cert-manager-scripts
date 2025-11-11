# Troubleshooting Guide

Common issues and solutions for cert-manager-scripts.

## Quick Test Issues

The `quick-test` runs a complete end-to-end workflow and may fail for several reasons.

### Common Issues

#### 1. Timeout waiting for certificate (5 minutes)

The test waits up to 5 minutes for the certificate to be issued.

**Symptoms:**
- Test hangs at "Waiting for certificate to be issued"
- Certificate remains in "Ready=False" state

**Debug commands:**
```bash
# Check cert-manager logs
oc logs -n cert-manager deployment/cert-manager --tail=50

# Check challenge status
oc get challenge -n default

# Check order status
oc get order -n default

# Verify Pebble is running
oc get pods -n pebble

# Check certificate details
oc describe certificate wildcard-test -n default
```

**Solutions:**
- Verify all components are running: `oc get pods -A | grep -E '(cert-manager|pebble|fake-dns)'`
- Check challenge logs: `oc describe challenge -n default`
- Restart cert-manager if needed: `oc rollout restart deployment/cert-manager -n cert-manager`

---

#### 2. DNS forwarding configuration failures

The fake DNS server needs to be configured in the cluster DNS operator.

**Symptoms:**
- DNS-01 challenges fail to validate
- Pebble cannot resolve DNS queries
- Error messages about DNS resolution

**Debug commands:**
```bash
# Check DNS operator status
oc get dns.operator.openshift.io/default -o yaml

# Verify fake-dns pod is running
oc get pods -n fake-dns

# Check DNS forwarding configuration
oc get dns.operator.openshift.io/default -o jsonpath='{.spec.servers}'

# Test DNS resolution from inside cluster
oc run dns-test --rm -i --tty --image=busybox --restart=Never -- nslookup example.com
```

**Solutions:**
- Ensure fake-dns is installed: `make install-fake-dns`
- Verify DNS forwarding is configured: Check `dns.operator.openshift.io/default` spec.servers
- Restart DNS pods if needed: `oc delete pods -n openshift-dns --all`
- Clean and reinstall: `make clean-fake-dns && make install-fake-dns`

---

#### 3. Pebble deployment issues

Pebble may fail to pull images or start correctly.

**Symptoms:**
- Pebble pod in `ImagePullBackOff` or `CrashLoopBackOff`
- Pebble service not accessible
- Connection timeouts to Pebble ACME endpoint

**Debug commands:**
```bash
# Check pod status
oc get pods -n pebble

# Check pod events
oc describe pod -n pebble

# Check pod logs
oc logs -n pebble deployment/pebble

# Verify network connectivity to image registry
oc debug node/<node-name> -- curl -I https://ghcr.io

# Test Pebble ACME endpoint from inside cluster
oc run pebble-test --rm -i --tty --image=curlimages/curl --restart=Never -- \
  curl -k https://pebble.pebble.svc.cluster.local:14000/dir
```

**Solutions:**
- Check image pull policy and registry access
- Verify Pebble deployment exists: `oc get deployment -n pebble`
- Check for resource constraints: `oc describe node`
- Reinstall Pebble: `make clean-pebble && make install-pebble`
- Use custom registry if needed: Edit `yaml/pebble/deployment.yaml` to use a mirror

---

#### 4. cert-manager-operator installation delays

The operator can take several minutes to install and become ready.

**Symptoms:**
- Operator stuck in "Installing" phase
- CSV not appearing or stuck in "Pending"
- cert-manager deployment not created

**Debug commands:**
```bash
# Check operator subscription
oc get subscription -n cert-manager-operator

# Check CSV status
oc get csv -n cert-manager-operator

# Check operator pod logs
oc logs -n cert-manager-operator deployment/cert-manager-operator-controller-manager

# Wait for cert-manager deployment
oc wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=5m

# Check operator conditions
oc get csv -n cert-manager-operator -o yaml | grep -A 10 conditions
```

**Solutions:**
- Wait longer (can take 5-10 minutes on first install)
- Check OLM catalog sources: `oc get catalogsource -n openshift-marketplace`
- Verify operator version is compatible with your OpenShift version
- Check for conflicting resources: `oc get csv -A | grep cert-manager`
- Reinstall operator: `make uninstall-cert-manager-operator && make install-cert-manager-operator`

---

#### 5. Resource constraints

Quick test requires sufficient cluster resources (CPU, memory).

**Symptoms:**
- Pods stuck in `Pending` state
- Eviction messages in pod events
- Node pressure warnings

**Debug commands:**
```bash
# Check node resources
oc describe nodes

# Check for pending pods
oc get pods -A | grep Pending

# Check resource quotas
oc get resourcequota -A

# Check for node pressure
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="MemoryPressure")].status}{"\t"}{.status.conditions[?(@.type=="DiskPressure")].status}{"\n"}{end}'

# Get resource usage
oc adm top nodes
oc adm top pods -A
```

**Solutions:**
- Add more resources to cluster nodes
- Reduce resource requests in deployments
- Delete unused pods/deployments
- Scale down non-essential workloads temporarily

---

## Recovery Steps

If the quick test fails, you can clean up and retry:

```bash
# Clean up everything
make clean

# Retry the quick test
make quick-test
```

Or run components individually to isolate the issue:

```bash
# Step 1: Install cert-manager-operator
make install-cert-manager-operator

# Step 2: Install fake DNS
make install-fake-dns

# Step 3: Install Pebble
DNS_SERVER=fake-dns-api.fake-dns.svc.cluster.local:53 PEBBLE_ALWAYS_VALID=1 make install-pebble

# Step 4: Create issuer and test certificate
make create-dns01-issuer
make test-cert
make verify-cert
```

---

## Certificate Issues

### Certificate stuck in "Issuing" state

**Symptoms:**
- Certificate shows `Ready=False` with reason "Issuing"
- CertificateRequest exists but not approved

**Debug:**
```bash
oc describe certificate <cert-name> -n <namespace>
oc get certificaterequest -n <namespace>
oc describe certificaterequest <request-name> -n <namespace>
```

**Solutions:**
- Wait longer (ACME validation can take time)
- Check challenge status: `oc get challenge -n <namespace>`
- Verify ClusterIssuer is ready: `oc get clusterissuer`
- Delete and recreate certificate

### Challenge validation failures

**Symptoms:**
- Challenge shows `state=invalid`
- Challenge stuck in `pending` state

**Debug:**
```bash
oc get challenge -n <namespace>
oc describe challenge <challenge-name> -n <namespace>
oc logs -n cert-manager deployment/cert-manager | grep -i challenge
```

**Solutions:**
- For HTTP-01: Verify ingress is created and accessible
- For DNS-01: Verify DNS records are created and resolvable
- Check Pebble logs: `oc logs -n pebble deployment/pebble`
- Verify ACME account is registered: `oc get secrets -n cert-manager | grep account`

---

## Workload Partitioning Issues

### cert-manager and Workload Partitioning

**Important:** cert-manager pods should NOT be configured with workload partitioning annotations in SNO/compact clusters.

**Check configuration:**
```bash
make check-workload-partitioning
```

**Why this matters:**
- Workload partitioning isolates management workloads to specific CPU sets
- cert-manager needs to run on all node types
- Restricting cert-manager can cause performance and accessibility issues

**Symptoms:**
- cert-manager webhook timeouts or failures
- Slow certificate issuance
- Pods only scheduled on management nodes

**Verification:**
The workload partitioning check verifies that cert-manager pods do NOT have the `target.workload.openshift.io/management` annotation.

**How to fix:**
If the check fails, remove workload partitioning annotations from:
1. CertManager custom resource
2. cert-manager namespace
3. cert-manager deployments

Then restart cert-manager pods:
```bash
oc rollout restart deployment/cert-manager -n cert-manager
oc rollout restart deployment/cert-manager-webhook -n cert-manager
oc rollout restart deployment/cert-manager-cainjector -n cert-manager
```

---

## Network Issues

For IPv4, IPv6, and dual-stack configuration issues, see [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md).

### Cannot reach Pebble ACME endpoint

**Symptoms:**
- cert-manager cannot connect to Pebble
- Connection refused or timeout errors

**Debug:**
```bash
# Check Pebble service
oc get svc -n pebble

# Test from inside cluster
oc run curl-test --rm -i --tty --image=curlimages/curl --restart=Never -- \
  curl -v -k https://pebble.pebble.svc.cluster.local:14000/dir

# Check network policies
oc get networkpolicy -A
```

**Solutions:**
- Verify Pebble service exists: `oc get svc pebble -n pebble`
- Check service endpoints: `oc get endpoints pebble -n pebble`
- Verify no network policies blocking traffic
- Restart Pebble: `oc rollout restart deployment/pebble -n pebble`

---

## Getting More Help

### Viewing Logs

```bash
# cert-manager logs
oc logs -n cert-manager deployment/cert-manager --tail=100 -f

# Pebble logs
oc logs -n pebble deployment/pebble --tail=100 -f

# fake-dns logs
oc logs -n fake-dns deployment/fake-dns-api --tail=100 -f

# cert-manager-operator logs
oc logs -n cert-manager-operator deployment/cert-manager-operator-controller-manager --tail=100 -f
```

### Useful Commands

```bash
# Get all cert-manager resources
oc get certificate,certificaterequest,order,challenge -A

# Get all ClusterIssuers
oc get clusterissuer

# Check operator health
oc get csv -A | grep cert-manager

# Check all pods status
oc get pods -A | grep -E '(cert-manager|pebble|fake-dns)'

# Export certificate details
oc get certificate <cert-name> -n <namespace> -o yaml

# View certificate from secret
oc get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

### Additional Resources

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Pebble GitHub](https://github.com/letsencrypt/pebble)
- [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) - Detailed Pebble usage guide
- [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md) - IPv4/IPv6/dual-stack guide
- [DNS01-SETUP.md](./DNS01-SETUP.md) - DNS-01 challenge setup guide

