# IBU Certificate Validation Testing

This guide explains how to validate cert-manager certificate behavior during Image-Based Upgrade (IBU) operations on SNO (Single Node OpenShift) clusters.

## Two Test Scenarios

This framework provides **two test scenarios** to validate different IBU behaviors:

| Scenario | Description | Expected Result |
|----------|-------------|-----------------|
| **Scenario 1: Certificate Loss** | Default IBU behavior - certificates are regenerated | Checksums DIFFER before/after |
| **Scenario 2: Certificate Preservation** | Using `lca.openshift.io/apply-label` annotation | Checksums MATCH before/after |

## Background

Image-Based Upgrade is a feature for upgrading Single Node OpenShift clusters by creating a seed image of the system and restoring it on the target node. By default, cert-manager certificates are **not preserved** during the upgrade process because certificate private keys are not backed up as part of the seed image.

However, the Lifecycle Agent (LCA) supports preserving specific resources using the `lca.openshift.io/apply-label` annotation. This annotation tells LCA which resources should be explicitly backed up and restored, allowing certificates to be preserved when needed.

**Red Hat Documentation Reference**: Certificates managed by cert-manager are regenerated after IBU unless explicitly preserved using the LCA apply-label mechanism.

## Testing Approach

Since IBU requires specific operators (Lifecycle Agent, TALM) and seed images, this framework uses **OADP (OpenShift API for Data Protection)** to simulate IBU behavior. The backup/restore cycle mimics what happens during IBU:

1. Backup certificate resources
2. Delete certificate resources (simulates upgrade)
3. Restore from backup
4. Observe that certificates are regenerated with new keys

## Prerequisites

- OpenShift 4.20+ cluster with default StorageClass
- `oc` CLI with cluster-admin privileges
- `jq` command-line JSON processor
- `envsubst` command (`brew install gettext` on macOS)
- Existing cert-manager installation

## Quick Start

```bash
# Run Scenario 1: Certificate Loss (default behavior)
make test-ibu-certs

# Run Scenario 2: Certificate Preservation (with LCA labels)
make test-ibu-preserved

# Run both scenarios
make test-ibu-both

# Full end-to-end test (installs all prerequisites + Scenario 1)
make quick-ibu-test
```

### Step-by-Step Setup

```bash
make install-cert-manager-operator  # If not already installed
make install-ibu-prereqs            # Install MinIO + OADP
make quick-dns-test                 # Create test certificates
make test-ibu-certs                 # Run Scenario 1 (loss)
make test-ibu-preserved             # Run Scenario 2 (preservation)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    IBU Test Components                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│  │   MinIO     │     │    OADP     │     │cert-manager │       │
│  │  (S3 Store) │◄────│   (Velero)  │────►│             │       │
│  └─────────────┘     └─────────────┘     └─────────────┘       │
│         │                   │                   │               │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Target Namespace (default)               │      │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐      │      │
│  │  │Certificate │  │Certificate │  │  TLS       │      │      │
│  │  │   CRs      │  │  Requests  │  │  Secrets   │      │      │
│  │  └────────────┘  └────────────┘  └────────────┘      │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Test Workflows

### Scenario 1: Certificate Loss (Default IBU Behavior)

```
┌──────────────────────────────────────────────────────────────────┐
│  Step 1: Capture Pre-IBU State                                   │
│  ─────────────────────────────────────────────────────────────── │
│  • Record all Certificate CRs                                    │
│  • Compute SHA256 checksums of TLS secret data                   │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 2: Simulate IBU via OADP (Standard Backup)                 │
│  ─────────────────────────────────────────────────────────────── │
│  • Create Velero backup (does not preserve raw cert data)        │
│  • Delete all certificates and TLS secrets                       │
│  • Restore from backup                                           │
│  • cert-manager regenerates new certificates                     │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 3: Validate Results                                        │
│  ─────────────────────────────────────────────────────────────── │
│  • Compare before/after checksums                                │
│  • EXPECTED: Checksums DIFFER (new certificates issued)          │
└──────────────────────────────────────────────────────────────────┘
```

### Scenario 2: Certificate Preservation (With LCA Labels)

```
┌──────────────────────────────────────────────────────────────────┐
│  Step 1: Label Resources for Preservation                        │
│  ─────────────────────────────────────────────────────────────── │
│  • Apply lca.openshift.io/backup label to Certificate CRs        │
│  • Apply lca.openshift.io/backup label to TLS Secrets            │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 2: Capture Pre-IBU State                                   │
│  ─────────────────────────────────────────────────────────────── │
│  • Record all Certificate CRs                                    │
│  • Compute SHA256 checksums of TLS secret data                   │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 3: Simulate IBU with Preserved Backup                      │
│  ─────────────────────────────────────────────────────────────── │
│  • Create Velero backup with labelSelector for labeled resources │
│  • Backup includes raw certificate and secret data               │
│  • Delete all certificates and TLS secrets                       │
│  • Restore from backup (original data restored)                  │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 4: Validate Results                                        │
│  ─────────────────────────────────────────────────────────────── │
│  • Compare before/after checksums                                │
│  • EXPECTED: Checksums MATCH (certificates preserved)            │
└──────────────────────────────────────────────────────────────────┘
```

## How LCA Apply-Label Works

The Lifecycle Agent uses the `lca.openshift.io/apply-label` annotation to specify which resources should be preserved during IBU:

1. **Annotation Format**: `<apiGroup>/<version>/<resourceType>/<namespace>/<resourceName>`
2. **LCA applies labels** to the specified resources: `lca.openshift.io/backup: <backup_name>`
3. **Backup CR uses labelSelector** to include only labeled resources
4. **Restore brings back original data** including certificate private keys

**Example Annotation:**
```yaml
metadata:
  annotations:
    lca.openshift.io/apply-label: >-
      cert-manager.io/v1/certificates/default/my-cert,
      v1/secrets/default/my-cert-tls
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make install-minio` | Install MinIO object storage |
| `make install-oadp` | Install OADP operator |
| `make install-ibu-prereqs` | Install both MinIO and OADP |
| `make capture-cert-state` | Capture current certificate state |
| `make test-ibu-certs` | Run Scenario 1: Certificate loss simulation |
| `make test-ibu-preserved` | Run Scenario 2: Certificate preservation test |
| `make test-ibu-both` | Run both scenarios sequentially |
| `make quick-ibu-test` | End-to-end test (prereqs + Scenario 1) |
| `make test-ibu-multi-algo` | Scenario 1 with ECDSA, RSA, and Ed25519 certs |
| `make clean-ibu` | Clean up all IBU test resources |

## Understanding Results

### Scenario 1: Expected Result - Certificates Lost

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IBU Certificate Loss Validation Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Total Secrets Compared:   1
  Changed (New Certs):      1
  Unchanged (Same Certs):   0
  Missing:                  0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  RESULT: EXPECTED BEHAVIOR CONFIRMED

  Certificates were NOT preserved during IBU simulation.
  All certificates received new keys/certs after restore.
```

This confirms the default IBU behavior: certificate data is lost and cert-manager regenerates new certificates.

### Scenario 2: Expected Result - Certificates Preserved

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IBU Certificate Preservation Validation Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Total Secrets Compared:   1
  Changed (New Certs):      0
  Unchanged (Same Certs):   1
  Missing:                  0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  RESULT: EXPECTED BEHAVIOR CONFIRMED

  Certificates WERE preserved during IBU simulation.
  All certificates retained their original keys/certs.
```

This confirms that using the LCA apply-label mechanism properly preserves certificates.

## When to Use Each Approach

| Scenario | Use Case |
|----------|----------|
| **Allow Regeneration (Default)** | Short-lived certificates, automated renewals, non-critical certs |
| **Preserve Certificates** | Long-lived CA certs, certificates shared with external systems, certs where regeneration causes issues |

## Components Installed

### MinIO

MinIO provides S3-compatible object storage for Velero backups:

- **Namespace**: `minio`
- **Storage**: 10Gi PVC
- **Credentials**: `minio` / `minio123`
- **Console**: Available via Route

### OADP (OpenShift API for Data Protection)

OADP installs Velero for backup/restore operations:

- **Namespace**: `openshift-adp`
- **Operator**: Red Hat OADP Operator (`stable` channel)
- **Backup Location**: MinIO S3 bucket `velero`

## State Files

The test creates state files in `/tmp/ibu-cert-state/`:

| File | Description |
|------|-------------|
| `certificates-before.json` | Certificate CRs before IBU |
| `certificates-after.json` | Certificate CRs after IBU |
| `checksums-before.json` | TLS secret checksums before IBU |
| `checksums-after.json` | TLS secret checksums after IBU |
| `issuers-before.json` | ClusterIssuers before IBU |
| `issuers-after.json` | ClusterIssuers after IBU |
| `validation-results.json` | Final comparison report |

## Troubleshooting

### MinIO Pod Not Starting

Check StorageClass and PVC:

```bash
oc get pvc -n minio
oc describe pvc minio-storage -n minio
oc get sc
```

### OADP Not Reconciling

Check operator and DPA status:

```bash
oc get csv -n openshift-adp
oc describe dpa velero -n openshift-adp
oc get backupstoragelocation -n openshift-adp
```

### Backup Fails

Check Velero logs:

```bash
oc logs -n openshift-adp deployment/velero
oc describe backup <backup-name> -n openshift-adp
```

### No Certificates Found

Ensure test certificates exist before running the test:

```bash
oc get certificates -n default
make quick-dns-test  # Create test certificates
```

## Cleanup

Remove all IBU test resources:

```bash
make clean-ibu
```

This removes:
- OADP operator and namespace
- MinIO namespace and storage
- Test certificates and backups
- State files in `/tmp/ibu-cert-state/`

## References

- [Red Hat OADP Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/backup_and_restore/oadp-application-backup-and-restore)
- [Image-Based Upgrade for SNO](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/edge_computing/image-based-upgrade-for-single-node-openshift-clusters)
- [cert-manager Operator for Red Hat OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
- [Red Hat Article 7057298](https://access.redhat.com/articles/7057298)
