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
./scripts/troubleshooting/check-certificate.sh <certificate-name> <namespace>
# or
make check-cert CERT=<name> NS=<namespace>
```

**Example:**
```bash
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
./scripts/troubleshooting/check-issuer.sh <clusterissuer-name>
# or
make check-issuer ISSUER=<name>
```

**Example:**
```bash
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

## Common Workflows

### Diagnosing a Failed Certificate

1. **Check the certificate:**
   ```bash
   make check-cert CERT=my-cert NS=default
   ```

2. **If HTTP-01 challenge, run HTTP-01 diagnostics:**
   ```bash
   make diagnose-http01
   ```

3. **If DNS-01 challenge, run DNS-01 diagnostics:**
   ```bash
   make diagnose-dns01
   ```

### Verifying ClusterIssuer Setup

```bash
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
- [guide/08-troubleshooting.md](../../guide/08-troubleshooting.md)

Use the guide for step-by-step manual troubleshooting, or use these scripts for automated diagnostics.

## Requirements

- OpenShift CLI (`oc`) installed and logged in
- `jq` for JSON parsing (optional, gracefully degrades without it)
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
1. Follow the existing format (colors, log functions)
2. Provide clear error messages and suggestions
3. Update this README
4. Add corresponding make target to Makefile

