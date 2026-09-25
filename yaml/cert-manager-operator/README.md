# cert-manager-operator

OpenShift cert-manager operator installation manifests. Installs the Red Hat-supported cert-manager operator from the OperatorHub catalog.

## Files

| File | Description |
|------|-------------|
| `operatorgroup.yaml` | OperatorGroup for the cert-manager-operator namespace |
| `subscription.yaml` | Subscription to install the operator from Red Hat catalog |

## Usage

```bash
# Install cert-manager-operator
make install-cert-manager-operator

# Or manually:
export OPERATOR_NAMESPACE="cert-manager-operator"
export OPERATOR_NAME="openshift-cert-manager-operator"
export CHANNEL="stable-v1"
export CERT_MANAGER_VERSION="v1.19.0"

envsubst < yaml/cert-manager-operator/operatorgroup.yaml | oc apply -f -
envsubst < yaml/cert-manager-operator/subscription.yaml | oc apply -f -
```

The Subscription uses manual InstallPlan approval to keep the requested starting CSV from automatically upgrading. When applying these templates manually, approve only the InstallPlan whose CSV matches `CERT_MANAGER_VERSION`; the install script performs this approval automatically.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_NAMESPACE` | `cert-manager-operator` | Namespace for the operator |
| `OPERATOR_NAME` | `openshift-cert-manager-operator` | Operator subscription name |
| `CHANNEL` | `stable-v1` | Update channel |
| `CERT_MANAGER_VERSION` | `v1.19.0` | Requested `startingCSV` version |

## Related Documentation

- [Installation](../../docs/installation.md) - Full installation guide
