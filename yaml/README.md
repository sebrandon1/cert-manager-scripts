# YAML Manifests

This directory contains Kubernetes/OpenShift YAML manifests organized by purpose.

## Structure

Each subdirectory represents a specific component or feature:

| Directory | Description | Files |
|-----------|-------------|-------|
| [`acme-dns/`](acme-dns/) | ACME-DNS server for DNS-01 challenge automation | 4 |
| [`cert-manager-operator/`](cert-manager-operator/) | OpenShift cert-manager operator installation | 2 |
| [`certificates/`](certificates/) | Test certificate templates | 1 |
| [`fake-dns-api/`](fake-dns-api/) | Air-gapped DNS testing server | 5 |
| [`issuers/`](issuers/) | ClusterIssuer configurations (HTTP-01, DNS-01) | 3 |
| [`pebble/`](pebble/) | Let's Encrypt Pebble ACME test server | 5 |
| [`pebble-challtestsrv/`](pebble-challtestsrv/) | Pebble challenge test server | 2 |
| [`ibu/`](ibu/) | IBU testing resources (MinIO, OADP, backups) | 3 subdirs |

See individual subdirectory READMEs for detailed documentation.

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

---

## pebble

### Files

- `namespace.yaml` - Namespace for Pebble deployment
- `configmap.yaml` - Pebble configuration (ACME server settings)
- `deployment.yaml` - Pebble deployment
- `service.yaml` - Service to expose Pebble within the cluster
- `route.yaml` - Route for external access to Pebble (if needed)

### Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `PEBBLE_NAMESPACE` | `pebble` | Namespace for Pebble |
| `DNS_SERVER` | `8.8.8.8:53` | DNS server for ACME validation |
| `PEBBLE_ALWAYS_VALID` | `0` | Auto-validate challenges (1=yes, 0=no) |

### What is Pebble?

Pebble is a lightweight ACME test server from Let's Encrypt. It:
- Provides a local ACME server for testing cert-manager
- Has no rate limits (unlike Let's Encrypt production)
- Can be configured to auto-validate challenges for easier testing
- Runs entirely in your OpenShift cluster

### Usage

These manifests are applied by `install-pebble.sh`:

```bash
export PEBBLE_NAMESPACE="pebble"
export DNS_SERVER="8.8.8.8:53"
export PEBBLE_ALWAYS_VALID="0"

envsubst < yaml/pebble/namespace.yaml | oc apply -f -
envsubst < yaml/pebble/configmap.yaml | oc apply -f -
envsubst < yaml/pebble/deployment.yaml | oc apply -f -
envsubst < yaml/pebble/service.yaml | oc apply -f -
envsubst < yaml/pebble/route.yaml | oc apply -f -
```

### Pebble Configuration

The `configmap.yaml` contains Pebble's configuration:
- **listenAddress**: ACME API endpoint (port 14000)
- **managementListenAddress**: Management API (port 15000)
- **httpPort/tlsPort**: Ports for HTTP-01 challenge validation
- **externalAccountBindingRequired**: Set to false for easier testing

### Accessing Pebble

After deployment, Pebble is accessible at:
- **Internal**: `https://pebble.pebble.svc.cluster.local:14000/dir`
- **External**: Through the OpenShift route (if route is created)

Use the internal URL when configuring cert-manager ClusterIssuers.
```

