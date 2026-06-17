# Installation Guide

Detailed installation instructions for cert-manager-scripts components.

## Prerequisites

Before running any scripts, ensure you have:

- **OpenShift cluster** (4.20+ recommended)
- **`oc` CLI** installed and configured
- **`envsubst`** command (part of gettext package)
  - macOS: `brew install gettext`
  - RHEL/Fedora: `dnf install gettext`
- **Cluster-admin privileges**
- **Bash shell** (for shell scripts)

## Quick Installation

### Option 1: Complete Setup (One Command)

Install everything with a single command:

```bash
make test-all
```

This will:
- Install cert-manager-operator
- Install Pebble with auto-validation enabled
- Create a ClusterIssuer pointing to Pebble
- Create test certificates

### Option 2: Step-by-Step Installation

Install components individually:

```bash
# Step 1: Install cert-manager-operator
make install-cert-manager-operator

# Step 2: Install Pebble ACME server
make install-pebble

# Step 3: Create ClusterIssuer
make create-issuer

# Step 4: Create test certificates
make create-certs
```

## Installation Scripts

### cert-manager-operator

#### Script: `scripts/install-cert-manager-operator.sh`

Installs the cert-manager Operator for Red Hat OpenShift following the official documentation.

**Usage:**
```bash
# Using the script directly
./scripts/install-cert-manager-operator.sh

# Or using Make (recommended)
make install-cert-manager-operator
```

**What it does:**
- Checks prerequisites (oc CLI, envsubst, cluster login, admin privileges)
- Creates the `cert-manager-operator` namespace
- Applies OperatorGroup and Subscription resources from YAML templates
- Uses `envsubst` for variable substitution in YAML files
- Waits for operator to be ready
- Verifies the installation
- Displays next steps
- **Idempotent**: Safe to run multiple times

**Reference:** [Red Hat OpenShift cert-manager Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)

---

### Pebble ACME Server

#### Script: `scripts/install-pebble.sh`

Installs Pebble, a local ACME test server, for testing cert-manager without hitting real Let's Encrypt servers.

**Usage:**
```bash
# Using the script directly
./scripts/install-pebble.sh

# Or using Make (recommended)
make install-pebble

# With custom configuration
PEBBLE_NAMESPACE=acme-test PEBBLE_ALWAYS_VALID=1 ./scripts/install-pebble.sh
```

**Configuration Options:**
| Variable | Default | Description |
|----------|---------|-------------|
| `PEBBLE_NAMESPACE` | `pebble` | Namespace for Pebble deployment |
| `DNS_SERVER` | `8.8.8.8:53` | DNS server Pebble uses for validation |
| `PEBBLE_ALWAYS_VALID` | `0` | Set to `1` to auto-validate all challenges |

**What it does:**
- Checks prerequisites
- Creates the Pebble namespace
- Deploys Pebble ACME server
- Creates a service for cluster-internal access
- Creates a route for external access (if needed)
- Waits for Pebble to be ready
- Displays ACME directory URL and next steps
- **Idempotent**: Safe to run multiple times

**When to use `PEBBLE_ALWAYS_VALID=1`:**
- Initial testing of cert-manager installation
- Testing certificate workflows without DNS/HTTP setup
- Quick validation of cert-manager configuration

**When to use `PEBBLE_ALWAYS_VALID=0`:**
- Testing real DNS-01 challenges
- Testing HTTP-01 challenges
- Validating your complete ACME setup

**Reference:** [Pebble GitHub Repository](https://github.com/letsencrypt/pebble)

**See also:** [Pebble Usage](./pebble-usage.md) for detailed usage guide, troubleshooting, and examples

---

### ClusterIssuer

#### Script: `scripts/create-issuer.sh`

Creates a cert-manager ClusterIssuer configured to use Pebble as the ACME server.

**Usage:**
```bash
# Using the script directly
./scripts/create-issuer.sh

# Or using Make (recommended)
make create-issuer

# With custom configuration
ISSUER_NAME=my-issuer ACME_EMAIL=admin@example.com ./scripts/create-issuer.sh
```

**Configuration Options:**
| Variable | Default | Description |
|----------|---------|-------------|
| `ISSUER_NAME` | `pebble-issuer` | Name for the ClusterIssuer |
| `ACME_SERVER_URL` | `https://pebble.pebble.svc.cluster.local:14000/dir` | ACME server URL |
| `ACME_EMAIL` | `test@example.com` | Email for ACME account registration |
| `INGRESS_CLASS` | `openshift-default` | Ingress class for HTTP-01 challenges |

**What it does:**
- Checks that cert-manager and Pebble are installed
- Creates a ClusterIssuer resource pointing to Pebble
- Configures HTTP-01 challenge solver
- Waits for issuer to be ready
- **Idempotent**: Safe to run multiple times

**Prerequisites:**
- cert-manager-operator must be installed
- Pebble should be installed (optional but recommended)

---

### Test Certificates

#### Script: `scripts/create-test-certificates.sh`

Creates multiple test certificates to verify cert-manager functionality.

**Usage:**
```bash
# Using the script directly
./scripts/create-test-certificates.sh

# Or using Make (recommended)
make create-certs

# With custom configuration
ISSUER_NAME=my-issuer CERT_NAMESPACE=test ./scripts/create-test-certificates.sh
```

**Configuration Options:**
| Variable | Default | Description |
|----------|---------|-------------|
| `ISSUER_NAME` | `pebble-issuer` | ClusterIssuer to use |
| `CERT_NAMESPACE` | `default` | Namespace for certificates |

**What it does:**
- Checks that cert-manager and ClusterIssuer exist
- Creates three test certificates:
  - `test-cert-simple` - Basic test certificate
  - `test-cert-app` - Application certificate
  - `test-cert-api` - API certificate
- Waits for certificates to be issued
- Displays status of all cert-manager resources
- **Idempotent**: Safe to run multiple times

**Note**: Certificates will only be issued if challenges can be validated. For quick testing, use `PEBBLE_ALWAYS_VALID=1` when installing Pebble.

---

### DNS-01 Challenges

For DNS-01 challenge testing with wildcard certificates, see [DNS-01 Setup](./dns01-setup.md) for detailed instructions on:
- Installing fake DNS API for air-gapped testing
- Configuring DNS forwarding
- Creating DNS-01 ClusterIssuers
- Testing wildcard certificates

## Verification

After installation, verify everything is working:

```bash
# Check installations
oc get pods -n cert-manager-operator
oc get pods -n cert-manager
oc get pods -n pebble

# Check cert-manager resources
oc get clusterissuer
oc get certificate -A
oc get certificaterequest,order,challenge -A
```

## Uninstalling

To remove components:

```bash
# Clean up certificates, issuers, and Pebble
make clean

# Uninstall cert-manager-operator (WARNING: use with caution)
make uninstall-cert-manager-operator
```

## Next Steps

After installing cert-manager-operator and Pebble, you can:

1. **Test certificate issuance:**
   - Create test certificates for applications
   - Test wildcard certificates with DNS-01 challenges
   - Verify HTTP-01 challenge handling

2. **Test production-like scenarios:**
   - Test apiServer certificate replacement
   - Test ingress certificate management
   - Test certificate renewal workflows

3. **Advanced testing:**
   - Configure DNS-01 challenges with custom DNS servers
   - Test IPv4, IPv6, and dual-stack configurations (see [Network Support](./network-support.md))
   - Set up monitoring and alerting for certificate expiry

