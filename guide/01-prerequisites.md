# Prerequisites

Before we begin, ensure you have the following requirements met.

## Required Tools

- OpenShift or Kubernetes cluster (v1.21+)
- `kubectl` or `oc` CLI installed and configured
- Cluster admin permissions

## Verify Cluster Access

Run this command to verify you can access your cluster:

```bash
oc cluster-info
```

You should see your cluster endpoint and services running.

## Check Network Configuration

Run the network check to ensure your cluster networking is properly configured:

```bash
make check-network
```

This will verify:
- Your cluster can reach external services
- Network policies allow proper communication
- DNS resolution is working

## What's Next?

Once your cluster is ready, you can proceed to install cert-manager.

---

**[Next Step: Install cert-manager →](02-install-cert-manager.md)**

