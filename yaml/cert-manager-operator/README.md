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

envsubst < yaml/cert-manager-operator/operatorgroup.yaml | oc apply -f -
envsubst < yaml/cert-manager-operator/subscription.yaml | oc apply -f -
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_NAMESPACE` | `cert-manager-operator` | Namespace for the operator |
| `OPERATOR_NAME` | `openshift-cert-manager-operator` | Operator subscription name |
| `CHANNEL` | `stable-v1` | Update channel |

## Related Documentation

- [Installation](../../docs/installation.md) - Full installation guide
