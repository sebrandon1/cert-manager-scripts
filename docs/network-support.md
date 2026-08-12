# IPv4, IPv6, and Dual-Stack Support

This document explains how IPv4, IPv6, and dual-stack networking affects cert-manager testing on OpenShift.

## Understanding Network Stacks

OpenShift clusters can be configured with three different network stack types:

### 1. IPv4 Only (Most Common)
- **What it means**: Cluster uses only IPv4 addresses for pod and service networks
- **Network CIDRs**: Only IPv4 CIDRs (e.g., `10.128.0.0/14`, `172.30.0.0/16`)
- **DNS Records**: Only A records needed
- **Typical setup**: Default for most OpenShift installations

### 2. IPv6 Only
- **What it means**: Cluster uses only IPv6 addresses for pod and service networks
- **Network CIDRs**: Only IPv6 CIDRs (e.g., `fd00:10:128::/56`)
- **DNS Records**: Only AAAA records needed
- **Typical setup**: Less common, used for IPv6-only environments

### 3. Dual-Stack (IPv4 + IPv6)
- **What it means**: Cluster supports both IPv4 and IPv6 simultaneously
- **Network CIDRs**: Both IPv4 and IPv6 CIDRs configured
- **DNS Records**: Both A and AAAA records can be used
- **Typical setup**: Available in OpenShift 4.14+ with OVN-Kubernetes
- **Flexibility**: Services can use either protocol or both

## Checking Your Cluster

Use the provided script to check your cluster's network configuration:

```bash
make check-network
```

This will display:
- OpenShift version
- Network plugin type (OVN-Kubernetes or OpenShift SDN)
- Cluster network CIDRs
- Service network CIDRs
- Network stack type (IPv4, IPv6, or dual-stack)
- Node IP addresses
- API server addresses

## Impact on cert-manager Testing

### cert-manager Compatibility

**Good news**: cert-manager works with all network stacks!

- ✅ IPv4 only clusters: Fully supported
- ✅ IPv6 only clusters: Fully supported
- ✅ Dual-stack clusters: Fully supported

cert-manager can:
- Communicate with ACME servers over IPv4 or IPv6
- Handle HTTP-01 challenges on any network stack
- Process DNS-01 challenges regardless of IP version
- Issue certificates for domains with A, AAAA, or both record types

### Pebble Compatibility

Pebble (the ACME test server) also supports all network stacks:

- Runs on IPv4, IPv6, or dual-stack clusters
- Accepts ACME requests over any protocol
- Validates challenges via IPv4 or IPv6
- No special configuration needed

### Testing Scenarios by Network Stack

#### IPv4 Only Cluster

**What you can test:**
- ✅ HTTP-01 challenges with IPv4
- ✅ DNS-01 challenges (DNS provider must be reachable via IPv4)
- ✅ Certificate issuance for domains with A records
- ✅ Wildcard certificates
- ✅ apiServer certificates
- ✅ Ingress/Route certificates

**Limitations:**
- ❌ Cannot test IPv6-specific scenarios
- ❌ Cannot test dual-stack service behavior

#### IPv6 Only Cluster

**What you can test:**
- ✅ HTTP-01 challenges with IPv6
- ✅ DNS-01 challenges (DNS provider must be reachable via IPv6)
- ✅ Certificate issuance for domains with AAAA records
- ✅ Wildcard certificates
- ✅ apiServer certificates
- ✅ Ingress/Route certificates

**Considerations:**
- Ensure external services (like DNS providers) support IPv6
- Some cloud providers may have limited IPv6 support
- Routes/Ingresses must be accessible via IPv6

#### Dual-Stack Cluster

**What you can test:**
- ✅ All IPv4 scenarios
- ✅ All IPv6 scenarios
- ✅ Services accessible via both protocols
- ✅ Protocol preference and fallback behavior
- ✅ Mixed environments (IPv4 clients to IPv6 services, etc.)

**Advantages for testing:**
- Most flexible configuration
- Can test real-world scenarios where clients use different protocols
- Can verify cert-manager works with both protocols

## DNS-01 Challenges and Network Stacks

### How DNS-01 Works with Different Stacks

DNS-01 challenges are **network-stack agnostic** because:

1. DNS providers typically accept API calls over both IPv4 and IPv6
2. ACME servers query DNS over whatever protocol they support
3. The actual DNS resolution happens externally

**Key Point**: DNS-01 challenges care about DNS records (TXT records for validation), not the cluster's internal IP addressing.

### IPv4 vs IPv6 for DNS-01

```
┌─────────────────────────────────────────────────────────┐
│                   DNS-01 Challenge Flow                  │
└─────────────────────────────────────────────────────────┘

cert-manager → DNS Provider API (IPv4 or IPv6)
     ↓
DNS Provider creates TXT record
     ↓
ACME Server (Pebble) → DNS Query (IPv4 or IPv6) → DNS Provider
     ↓
Validation succeeds if TXT record matches
```

The cluster's network stack **doesn't matter** for DNS-01 as long as:
- cert-manager can reach the DNS provider's API
- The ACME server can query DNS

## HTTP-01 Challenges and Network Stacks

### How HTTP-01 Works with Different Stacks

HTTP-01 challenges **are affected** by network stack because:

1. ACME server must make HTTP connection to your cluster
2. The route/ingress must be accessible from ACME server
3. IP version must match between ACME server and cluster

### IPv4 Only Cluster with HTTP-01

```yaml
# Example: HTTP-01 challenge on IPv4 cluster
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
spec:
  dnsNames:
  - example.com  # Must have A record pointing to IPv4 address
  issuerRef:
    name: pebble-issuer
    kind: ClusterIssuer
```

**Requirements:**
- Domain must have A record
- Route must be accessible via IPv4
- Pebble can reach route via IPv4

### IPv6 Only Cluster with HTTP-01

```yaml
# Example: HTTP-01 challenge on IPv6 cluster
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert-ipv6
spec:
  dnsNames:
  - example.com  # Must have AAAA record pointing to IPv6 address
  issuerRef:
    name: pebble-issuer
    kind: ClusterIssuer
```

**Requirements:**
- Domain must have AAAA record
- Route must be accessible via IPv6
- Pebble can reach route via IPv6

### Dual-Stack Cluster with HTTP-01

**Advantages:**
- Works with domains that have A, AAAA, or both records
- ACME server can use either protocol
- More forgiving configuration

## Testing Recommendations by Scenario

### Scenario 1: Testing with Pebble (Local ACME)

**With `PEBBLE_ALWAYS_VALID=1`:**
- Network stack doesn't matter
- All challenges auto-succeed
- Great for initial cert-manager testing
- No external connectivity required

**With `PEBBLE_ALWAYS_VALID=0`:**
- Must configure DNS or HTTP routes properly
- Network stack matters for HTTP-01
- Good for realistic testing

### Scenario 2: Testing with Let's Encrypt Staging

**IPv4 Only:**
- Standard configuration
- Ensure routes are accessible from internet via IPv4

**IPv6 Only:**
- Requires IPv6 connectivity to Let's Encrypt
- Routes must be accessible via IPv6
- Less common, verify Let's Encrypt IPv6 support

**Dual-Stack:**
- Most flexible
- Let's Encrypt can use either protocol

## Common Issues by Network Stack

### IPv4 Only Issues

**Issue**: "Connection refused" to external services
- **Cause**: Service only supports IPv6
- **Solution**: Ensure all external services support IPv4

### IPv6 Only Issues

**Issue**: "No route to host" errors
- **Cause**: External service doesn't support IPv6
- **Solution**: Verify external services have IPv6 connectivity

**Issue**: DNS resolution failures
- **Cause**: DNS provider doesn't have AAAA records
- **Solution**: Ensure DNS provider supports IPv6

### Dual-Stack Issues

**Issue**: Unexpected protocol being used
- **Cause**: Service prefers one protocol over another
- **Solution**: Explicitly configure protocol preference

## Network Stack Detection in Scripts

### Current Behavior

The toolkit includes network stack auto-detection via `scripts/troubleshooting/check-network-stack.sh` and `scripts/check-cluster-network.sh`. You can run it with:

```bash
make check-network
```

This will detect and display:
- Network stack type (IPv4, IPv6, or dual-stack)
- Cluster and service network CIDRs
- Node IP addresses and API server addresses
- Recommendations for testing

### Why Don't Installation Scripts Adapt Based on Network Stack?

1. **cert-manager works with all stacks** - no need to modify installation
2. **Pebble works with all stacks** - no configuration changes needed
3. **Flexibility** - users might want to test specific scenarios

### When to Check Network Configuration

**Recommended to check before:**
- Testing IPv6-specific scenarios
- Configuring HTTP-01 challenges with external domains
- Setting up DNS records for challenges
- Troubleshooting connectivity issues

**Not necessary for:**
- Basic cert-manager installation
- Pebble installation with `PEBBLE_ALWAYS_VALID=1`
- Testing with DNS-01 challenges

## Summary

| Aspect | IPv4 Only | IPv6 Only | Dual-Stack |
|--------|-----------|-----------|------------|
| cert-manager support | ✅ Full | ✅ Full | ✅ Full |
| Pebble support | ✅ Full | ✅ Full | ✅ Full |
| HTTP-01 challenges | ✅ A records | ✅ AAAA records | ✅ Both |
| DNS-01 challenges | ✅ Works | ✅ Works | ✅ Works |
| Testing flexibility | Medium | Medium | High |
| Most common | ✅ Yes | No | Emerging |

## References

- [OpenShift Dual-Stack Documentation](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes IPv6 Documentation](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)

