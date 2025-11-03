# YAML Manifests

This directory contains Kubernetes/OpenShift YAML manifests organized by purpose.

## Structure

Each subdirectory represents a specific component or feature:

- `cert-manager-operator/` - Manifests for installing the cert-manager Operator

## Variable Substitution

The YAML files use environment variable placeholders in the format `${VARIABLE_NAME}`. These are substituted at runtime using the `envsubst` command.

### Example

**YAML template:**
```yaml
metadata:
  name: ${OPERATOR_NAME}
  namespace: ${OPERATOR_NAMESPACE}
```

**After substitution:**
```yaml
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
```

## Adding New Manifests

When adding new YAML manifests:

1. Create a subdirectory for your component (e.g., `yaml/issuers/`)
2. Use environment variable placeholders for configurable values
3. Export the variables in your shell script
4. Use `envsubst < template.yaml | oc apply -f -` to apply with substitution
5. Document the variables in a README or comments

## cert-manager-operator

### Files

- `operatorgroup.yaml` - Defines the OperatorGroup for the cert-manager-operator
- `subscription.yaml` - Defines the Subscription to install the operator from RedHat catalog

### Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `OPERATOR_NAMESPACE` | `cert-manager-operator` | Namespace for the operator |
| `OPERATOR_NAME` | `openshift-cert-manager-operator` | Name of the operator subscription |
| `CHANNEL` | `stable-v1` | Update channel for the operator |

### Usage

These manifests are applied by `install-cert-manager-operator.sh`:

```bash
export OPERATOR_NAMESPACE="cert-manager-operator"
export OPERATOR_NAME="openshift-cert-manager-operator"
export CHANNEL="stable-v1"

envsubst < yaml/cert-manager-operator/operatorgroup.yaml | oc apply -f -
envsubst < yaml/cert-manager-operator/subscription.yaml | oc apply -f -
```

