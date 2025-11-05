# cert-manager-scripts

A collection of scripts for testing and managing cert-manager-operator on OpenShift clusters.

## Overview

This repository contains bash and Python scripts for:
- Installing and configuring cert-manager-operator
- Testing certificate issuance scenarios (wildcard, apiServer, application certs)
- Verifying DNS-01 and HTTP-01 challenges
- Testing IPv4, IPv6, and dual-stack configurations
- Setting up local ACME testing environments

## Prerequisites

- OpenShift cluster (4.20+ recommended)
- `oc` CLI installed and configured
- `envsubst` command (part of gettext package)
  - macOS: `brew install gettext`
  - RHEL/Fedora: `dnf install gettext`
- Cluster-admin privileges
- Bash shell (for shell scripts)

## Quick Test (3 Commands!)

Want to quickly test DNS-01 certificate issuance? Just run these 3 commands:

```bash
# 1. Install cert-manager-operator (if not already installed)
make install-cert-manager-operator

# 2. Run the quick test (sets up everything and tests)
make quick-test

# 3. Clean up when done
make clean
```

That's it! The `quick-test` target will:
- Install Pebble ACME server (air-gapped)
- Install fake DNS server (for DNS-01 challenges)
- Configure DNS forwarding
- Create a DNS-01 ClusterIssuer
- Request a wildcard certificate (`*.example.com`)
- Verify the certificate status

**Note:** If the certificate isn't ready after 30 seconds, you can check progress with:
```bash
make verify-cert
```

## What is Pebble?

**Pebble** is a small ACME test server developed by the Let's Encrypt team. It mimics the behavior of Let's Encrypt's production ACME server but runs locally in your cluster. This is perfect for testing cert-manager without:
- Hitting Let's Encrypt rate limits
- Needing real public DNS records
- Requiring internet connectivity
- Dealing with production certificate concerns

**Key Benefits:**
- **No rate limits** - test as much as you want
- **Fast** - instant certificate issuance
- **Local** - runs entirely in your OpenShift cluster
- **Safe** - doesn't issue real certificates
- **Configurable** - can be set to auto-validate challenges for testing

## Repository Structure

```
cert-manager-scripts/
├── Makefile                            # Make targets for common tasks
├── README.md                           # This file
├── PEBBLE-USAGE.md                     # Detailed Pebble usage guide
├── NETWORK-SUPPORT.md                  # IPv4/IPv6/dual-stack guide
├── check-cluster-network.sh            # Check IPv4/IPv6/dual-stack support
├── install-cert-manager-operator.sh    # Install cert-manager-operator
├── install-pebble.sh                   # Install Pebble ACME server
├── create-issuer.sh                    # Create ClusterIssuer
├── create-test-certificates.sh         # Create test certificates
└── yaml/                               # YAML manifests organized by purpose
    ├── README.md                       # YAML documentation
    ├── cert-manager-operator/
    │   ├── operatorgroup.yaml          # OperatorGroup definition
    │   └── subscription.yaml           # Subscription definition
    ├── pebble/
    │   ├── namespace.yaml              # Pebble namespace
    │   ├── configmap.yaml              # Pebble configuration
    │   ├── deployment.yaml             # Pebble deployment
    │   ├── service.yaml                # Pebble service
    │   └── route.yaml                  # Pebble route (external access)
    ├── issuers/
    │   └── pebble-clusterissuer.yaml   # ClusterIssuer for Pebble
    └── certificates/
        └── test-certificate.yaml       # Test certificate template
```

## Scripts

### Utility Scripts

#### `check-cluster-network.sh`

Checks your OpenShift cluster's network configuration to determine IPv4, IPv6, or dual-stack support.

**Usage:**
```bash
# Using the script directly
./check-cluster-network.sh

# Or using Make
make check-network

# Export as JSON for scripting
EXPORT_FORMAT=json ./check-cluster-network.sh
```

**What it checks:**
- OpenShift version
- Network plugin type (OVN-Kubernetes, OpenShift SDN)
- Cluster network CIDRs (IPv4/IPv6)
- Service network CIDRs
- API server addresses
- Node IP addresses
- Network stack type (IPv4 only, IPv6 only, or dual-stack)

**Why this matters:**
- Understand what network testing scenarios are possible on your cluster
- Verify IPv6 or dual-stack support before testing
- Ensure your cluster configuration matches your testing requirements
- cert-manager and Pebble work with all network stacks, but knowing yours helps with troubleshooting

**Output example:**
```
Network Stack: DUAL-STACK (IPv4 + IPv6)
  ✓ IPv4 support: Enabled
  ✓ IPv6 support: Enabled
  ✓ Dual-stack: Enabled
```

**See also:** [NETWORK-SUPPORT.md](./NETWORK-SUPPORT.md) for detailed information about IPv4, IPv6, and dual-stack testing

---

### Installation Scripts

#### `install-cert-manager-operator.sh`

Installs the cert-manager Operator for Red Hat OpenShift following the official documentation.

**Usage:**
```bash
# Using the script directly
./install-cert-manager-operator.sh

# Or using Make
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

#### `install-pebble.sh`

Installs Pebble, a local ACME test server, for testing cert-manager without hitting real Let's Encrypt servers.

**Usage:**
```bash
# Using the script directly
./install-pebble.sh

# Or using Make
make install-pebble

# With custom configuration
PEBBLE_NAMESPACE=acme-test PEBBLE_ALWAYS_VALID=1 ./install-pebble.sh
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

**See also:** [PEBBLE-USAGE.md](./PEBBLE-USAGE.md) for detailed usage guide, troubleshooting, and examples

---

#### `create-issuer.sh`

Creates a cert-manager ClusterIssuer configured to use Pebble as the ACME server.

**Usage:**
```bash
# Using the script directly
./create-issuer.sh

# Or using Make
make create-issuer

# With custom configuration
ISSUER_NAME=my-issuer ACME_EMAIL=admin@example.com ./create-issuer.sh
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

#### `create-test-certificates.sh`

Creates multiple test certificates to verify cert-manager functionality.

**Usage:**
```bash
# Using the script directly
./create-test-certificates.sh

# Or using Make
make create-certs

# With custom configuration
ISSUER_NAME=my-issuer CERT_NAMESPACE=test ./create-test-certificates.sh
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

## Getting Started

### Quick Start - Install Everything

1. Clone this repository:
   ```bash
   git clone <repo-url>
   cd cert-manager-scripts
   ```

2. Log in to your OpenShift cluster:
   ```bash
   oc login <cluster-url>
   ```

3. **(Recommended)** Check your cluster's network configuration:
   ```bash
   make check-network
   ```
   
   This will show you if your cluster supports IPv4, IPv6, or dual-stack networking, which helps you understand what testing scenarios are possible.

4. **Complete setup with one command:**
   ```bash
   make test-all
   ```
   
   This will:
   - Install cert-manager-operator
   - Install Pebble with auto-validation enabled
   - Create a ClusterIssuer pointing to Pebble
   - Create test certificates
   
   **OR** install components step-by-step:
   ```bash
   make install-all        # Install cert-manager + Pebble
   make create-issuer      # Create ClusterIssuer
   make create-certs       # Create test certificates
   ```

5. Verify everything is working:
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

### Step-by-Step Installation

If you prefer to install components individually:

1. **Install cert-manager-operator:**
   ```bash
   make install-cert-manager-operator
   ```

2. **Install Pebble (optional, for local testing):**
   ```bash
   make install-pebble
   ```
   
   Or with auto-validation enabled:
   ```bash
   PEBBLE_ALWAYS_VALID=1 make install-pebble
   ```

## Makefile Targets

Run `make help` to see all available targets:

```bash
make help
```

### Quick Testing
- `make quick-test` - Complete end-to-end DNS-01 test (setup + test + verify)
- `make test-cert` - Create a test wildcard certificate
- `make verify-cert` - Check certificate status

### Available targets:
- `make check-network` - Check cluster network configuration (IPv4/IPv6/dual-stack)
- `make install-cert-manager-operator` - Install cert-manager Operator
- `make install-pebble` - Install Pebble ACME test server
- `make install-all` - Install both cert-manager-operator and Pebble
- `make create-issuer` - Create ClusterIssuer pointing to Pebble
- `make create-certs` - Create test certificates
- `make test-all` - **Complete setup: install + configure + test**
- `make uninstall-cert-manager-operator` - Uninstall cert-manager Operator (coming soon)
- `make clean` - Clean up temporary files
- `make help` - Show help message

## Next Steps

After installing cert-manager-operator and Pebble, you can:

1. **Configure a cert-manager ClusterIssuer pointing to Pebble:**
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: pebble-issuer
   spec:
     acme:
       server: https://pebble.pebble.svc.cluster.local:14000/dir
       skipTLSVerify: true  # Pebble uses self-signed certs
       privateKeySecretRef:
         name: pebble-private-key
       solvers:
       - http01:
           ingress:
             class: nginx
   ```

2. **Test certificate issuance:**
   - Create test certificates for applications
   - Test wildcard certificates with DNS-01 challenges
   - Verify HTTP-01 challenge handling

3. **Test production-like scenarios:**
   - Test apiServer certificate replacement
   - Test ingress certificate management
   - Test certificate renewal workflows

4. **Advanced testing:**
   - Configure DNS-01 challenges with custom DNS servers
   - Test IPv4, IPv6, and dual-stack configurations
   - Set up monitoring and alerting for certificate expiry

## Contributing

This is a collection of testing and utility scripts. Feel free to add new scripts or improve existing ones.

## License

Apache 2.0
