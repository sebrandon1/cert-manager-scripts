# Troubleshooting Scripts

Automated diagnostic tools to help quickly identify and resolve cert-manager issues.

## Quick Start

Run all diagnostics:
```bash
make troubleshoot
# or
./scripts/troubleshooting/check-all.sh
```

## Available Scripts

### 1. check-all.sh
**Description:** Comprehensive system health check  
**Usage:**
```bash
./scripts/troubleshooting/check-all.sh
# or
make troubleshoot
```

**Checks:**
- cert-manager operator and components
- Pebble ACME server
- DNS-01 components (fake DNS API)
- All ClusterIssuers
- All Certificates
- Active Challenges
- Overall health summary

---

### 2. check-certificate.sh
**Description:** Detailed certificate diagnostics  
**Usage:**
```bash
# Check all certificates across all namespaces
./scripts/troubleshooting/check-certificate.sh

# Check specific certificate
./scripts/troubleshooting/check-certificate.sh <certificate-name> <namespace>

# Or use make commands
make check-cert CERT=<name> NS=<namespace>
```

**Examples:**
```bash
# Check all certificates
./scripts/troubleshooting/check-certificate.sh

# Check specific certificate
./scripts/troubleshooting/check-certificate.sh test-cert-simple default
make check-cert CERT=test-cert-simple NS=default
```

**Provides:**
- Certificate status and readiness
- Secret details
- CertificateRequest status
- ACME Order details
- Challenge information
- Helpful troubleshooting commands

---

### 3. check-issuer.sh
**Description:** ClusterIssuer configuration and status check  
**Usage:**
```bash
# Check all ClusterIssuers
./scripts/troubleshooting/check-issuer.sh

# Check specific ClusterIssuer
./scripts/troubleshooting/check-issuer.sh <clusterissuer-name>

# Or use make commands
make check-issuer ISSUER=<name>
```

**Examples:**
```bash
# Check all ClusterIssuers
./scripts/troubleshooting/check-issuer.sh

# Check specific ClusterIssuers
./scripts/troubleshooting/check-issuer.sh pebble-issuer
make check-issuer ISSUER=pebble-issuer
make check-issuer ISSUER=pebble-dns01-issuer
```

**Provides:**
- Issuer readiness status
- ACME server configuration
- Solver type (HTTP-01 or DNS-01)
- Ingress class configuration
- ACME server connectivity test
- Full configuration details

---

### 4. diagnose-http01.sh
**Description:** HTTP-01 challenge diagnostics  
**Usage:**
```bash
./scripts/troubleshooting/diagnose-http01.sh
# or
make diagnose-http01
```

**Checks:**
- cert-manager deployment status
- Pebble ACME server availability
- HTTP-01 ClusterIssuers
- Active HTTP-01 challenges
- Challenge solver services
- Network connectivity
- Recent logs from cert-manager and Pebble

**Use When:**
- HTTP-01 certificates are failing
- Challenges are stuck in pending state
- Need to verify HTTP-01 setup

---

### 5. diagnose-dns01.sh
**Description:** DNS-01 challenge diagnostics  
**Usage:**
```bash
./scripts/troubleshooting/diagnose-dns01.sh
# or
make diagnose-dns01
```

**Checks:**
- cert-manager deployment status
- Pebble ACME server (including ALWAYS_VALID setting)
- Challenge test server
- Fake DNS API (for air-gapped setups)
- DNS-01 ClusterIssuers
- Active DNS-01 challenges
- RFC2136 credentials
- Recent logs from all DNS-01 components

**Use When:**
- DNS-01/wildcard certificates are failing
- Need to verify DNS-01 setup
- Debugging air-gapped DNS configurations

---

### 6. check-workload-partitioning.sh
**Description:** Verify cert-manager pods are NOT using workload partitioning  
**Usage:**
```bash
./scripts/troubleshooting/check-workload-partitioning.sh
# or
make check-workload-partitioning
```

**Checks:**
- cert-manager pod annotations for workload partitioning
- Deployment template annotations
- Provides recommendations if issues are found

**Provides:**
- Status of each cert-manager pod
- Workload partitioning annotation detection
- Deployment configuration verification
- Recommendations for fixing issues

**Why This Matters:**
Workload partitioning is used to isolate management workloads in SNO/compact clusters. cert-manager should NOT be configured with workload partitioning because:
- cert-manager needs to run on all node types
- Restricting to management CPU sets can cause performance issues
- cert-manager webhook needs to be accessible cluster-wide

**Use When:**
- Verifying cert-manager configuration on SNO/compact clusters
- Troubleshooting cert-manager performance issues
- Validating cluster configuration before RAN/Edge deployments

---

### 7. verify-apiserver-certificate.sh
**Description:** Verify that cert-manager issued API server certificate doesn't break cluster access  
**Usage:**
```bash
./scripts/troubleshooting/verify-apiserver-certificate.sh
# or
make verify-apiserver-cert
```

**Checks:**
- API server is accessible
- Certificate is properly issued and valid
- oc commands work correctly
- Certificate details match expected values
- API server configuration

**Provides:**
- API server connectivity verification
- Certificate status and expiration
- Certificate SANs and issuer details
- Recommendations if issues are detected

**Why This Matters:**
API server certificates are critical for cluster access. This verifies that:
- cert-manager can safely manage API server certificates
- Certificates don't break cluster connectivity
- Certificate renewal won't cause outages
- Useful for RAN/Core/Hub deployments where cert-manager manages critical certificates

**Use When:**
- After creating API server certificates with cert-manager
- Validating cert-manager integration with API server
- Troubleshooting cluster access issues
- Testing certificate renewal scenarios
- Verifying RAN/Edge cluster configurations

---

### 8. check-cert-renewal.sh
**Description:** Certificate renewal status and upcoming renewals  
**Usage:**
```bash
./scripts/troubleshooting/check-cert-renewal.sh
make check-cert-renewal
```

---

### 9. verify-monitoring.sh
**Description:** Verify cert-manager ServiceMonitor and PrometheusRule  
**Usage:**
```bash
./scripts/troubleshooting/verify-monitoring.sh
make verify-monitoring
```

---

### 10. check-network-stack.sh
**Description:** Detect IPv4, IPv6, or dual-stack  
**Usage:**
```bash
./scripts/troubleshooting/check-network-stack.sh
make check-network-stack
```

`make check-network` runs the broader `scripts/check-cluster-network.sh` check.

---

## Common Workflows

### Diagnosing a Failed Certificate

1. **Check all certificates to identify issues:**
   ```bash
   ./scripts/troubleshooting/check-certificate.sh
   ```

2. **Or check a specific certificate:**
   ```bash
   make check-cert CERT=my-cert NS=default
   ```

3. **If HTTP-01 challenge, run HTTP-01 diagnostics:**
   ```bash
   make diagnose-http01
   ```

4. **If DNS-01 challenge, run DNS-01 diagnostics:**
   ```bash
   make diagnose-dns01
   ```

### Verifying ClusterIssuer Setup

```bash
# Check all ClusterIssuers
./scripts/troubleshooting/check-issuer.sh

# Check specific issuer
make check-issuer ISSUER=pebble-issuer

# Run all diagnostics
make troubleshoot
```

### Quick Health Check

```bash
# Run all diagnostics to get overall system health
make troubleshoot
```

## Output Features

All scripts provide:
- ✅ **Green checkmarks** for successful checks
- ⚠️ **Warnings** for potential issues
- ❌ **Errors** for critical problems
- 📋 **Detailed information** about components
- 💡 **Helpful suggestions** and next steps

## Integration with Guides

These scripts correspond to the troubleshooting sections in:
- [docs/troubleshooting.md](../../docs/troubleshooting.md)

Use the guide for step-by-step manual troubleshooting, or use these scripts for automated diagnostics.

## Requirements

- OpenShift CLI (`oc`) installed and logged in
- `jq` for JSON parsing (`make troubleshoot` / `check-all.sh` requires it)
- Access to the cluster with appropriate permissions

## Tips

1. **Start broad, then narrow:**
   - Run `make troubleshoot` first for overview
   - Use specific scripts for detailed diagnostics

2. **Check logs when needed:**
   - Scripts show recent logs
   - Follow full logs if issues persist:
     ```bash
     oc logs -n cert-manager deployment/cert-manager -f
     oc logs -n pebble -l app=pebble -f
     ```

3. **Use with make commands:**
   - All scripts are integrated with the Makefile
   - See `make help` for all available commands

## Contributing

When adding new troubleshooting scripts:
1. Source `lib/common.sh` — do not redefine colors or logging
2. Provide clear error messages and suggestions
3. Update this README
4. Add a Makefile target with a `## Description` comment

