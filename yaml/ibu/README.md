# IBU (Image-Based Upgrade) Testing

Resources for testing cert-manager certificate behavior during OpenShift Image-Based Upgrade (IBU) operations. Includes MinIO object storage, OADP operator configuration, and Velero backup/restore manifests.

## Subdirectories

| Directory | Description |
|-----------|-------------|
| `minio/` | MinIO S3-compatible object storage for backup destination |
| `oadp/` | OADP (OpenShift API for Data Protection) operator installation |
| `backup/` | Velero Backup and Restore manifests for IBU simulation |

## Quick Start

```bash
# Install all IBU prerequisites (MinIO + OADP)
make install-ibu-prereqs

# Run the full IBU certificate loss simulation
make test-ibu-certs

# Or run the end-to-end test
make quick-ibu-test

# Clean up
make clean-ibu
```

## Components

### MinIO (`minio/`)
S3-compatible object storage used as the backup destination for Velero. Includes deployment, service, route, PVC, and credentials.

### OADP (`oadp/`)
OpenShift API for Data Protection operator. Configures Velero with AWS, OpenShift, and CSI plugins pointing to the MinIO instance.

### Backup (`backup/`)
Velero Backup and Restore CRs that simulate IBU behavior:
- `backup.yaml` / `restore.yaml` - Default behavior (certificates regenerated)
- `backup-preserved.yaml` / `restore-preserved.yaml` - LCA label preservation

## Test Scenarios

| Scenario | Backup CR | Result |
|----------|-----------|--------|
| **Scenario 1 (Default)** | `backup.yaml` | Certificates regenerated with new keys |
| **Scenario 2 (Preserved)** | `backup-preserved.yaml` | Certificates preserved via LCA labels |

## How It Works

1. **MinIO** provides S3-compatible storage within the cluster
2. **OADP/Velero** handles backup and restore operations
3. **Backup CRs** capture certificate resources (with or without TLS secrets)
4. **Restore CRs** restore resources, triggering cert-manager reconciliation

The key difference between scenarios is whether the `lca.openshift.io/backup` label is applied to TLS secrets, which determines if private key material is preserved.

## Related Documentation

- [IBU Testing](../../docs/ibu-testing.md) - Full IBU testing guide
- [docs/IBU-FAQ.md](../../docs/IBU-FAQ.md) - Frequently asked questions
- [Validation Report](https://gist.github.com/sebrandon1/71f33b35aea2aa4cf9edda855201c8fc)
