# IBU Certificate Testing FAQ

Frequently asked questions about cert-manager certificate behavior during OpenShift Image-Based Upgrade (IBU) operations.

## General

### Does this testing address IBU certificate concerns?

Yes. The testing validates two scenarios:

| Scenario | Behavior | Result |
|----------|----------|--------|
| **Scenario 1 (Default)** | Standard backup/restore | Certificates regenerated - checksums differ before/after |
| **Scenario 2 (LCA Labels)** | Resources labeled with `lca.openshift.io/apply-label` | Certificates preserved - checksums match exactly |

Customers who need to preserve specific certs through IBU (like long-lived CAs or certs shared with external systems) have an option - they just need to use the apply-label mechanism.

Full report: https://gist.github.com/sebrandon1/71f33b35aea2aa4cf9edda855201c8fc

### Does Scenario 1 use apply-label, or is it default IBU behavior?

Scenario 1 is **default IBU behavior with no special handling**.

The Scenario 1 backup (`backup.yaml`) uses a generic labelSelector:
```yaml
labelSelector:
  matchExpressions:
    - key: app
      operator: Exists
```

This picks up app-labeled resources but does NOT use any `lca.openshift.io/*` labels or annotations. It represents what happens during IBU when no cert-manager-specific preservation steps are taken.

**Comparison:**

| Scenario | Backup CR | Labels Used | Result |
|----------|-----------|-------------|--------|
| **Scenario 1** | `backup.yaml` | Generic `app` label | Certs regenerated (default behavior) |
| **Scenario 2** | `backup-preserved.yaml` | `lca.openshift.io/backup` | Certs preserved |

So Scenario 1 confirms the known limitation: without explicit preservation steps, cert-manager certificates are lost during IBU and get reissued with new keys.

---

## Certificate Reissuance

### Is the cert immediately reissued or does it wait until expiration?

**Immediately.** In Scenario 1, the sequence is:

1. Backup captures the Certificate CR (metadata) but the standard backup does NOT include the raw TLS secret data (private keys are excluded)
2. Restore brings back the Certificate CR
3. cert-manager sees the Certificate CR exists but the TLS secret is missing or has invalid data
4. cert-manager immediately reconciles and triggers new certificate issuance

cert-manager doesn't wait for expiration - it detects the missing/invalid secret right away and reissues. The new cert will have a fresh validity period starting from that moment.

In the simulation script (`simulate-ibu-backup-restore.sh`), stale CertificateRequests must be deleted because cert-manager tries to reconcile immediately:

```bash
# Delete restored CertificateRequests to allow cert-manager to create new ones
# The restored CRs have stale data and block new certificate issuance
oc delete certificaterequests --all -n "$TARGET_NAMESPACE" --ignore-not-found=true
```

---

## Certificate Preservation

### Are certificates "preserved" exactly, or recreated and restored?

The certificates are **not preserved in place**. The sequence is:

1. Backup captures the raw cert data including private keys
2. IBU wipes the node and restores from seed image
3. Restore brings back the original certificate data

There IS a period where the cert doesn't exist, and restore does cause cert-manager to reconcile. For the API server cert specifically, this means a rollout and approximately 1-2 minutes added to IBU duration.

The benefit is that the *same* certificate/key material comes back (matching checksums) rather than getting entirely new certs issued - important for certs shared with external systems or where key continuity matters.

---

## Labeling Workflow

### What is the workflow for labeling certs?

The workflow uses the `lca.openshift.io/apply-label` annotation on the IBU Backup CR. You specify resources in this format:

```
lca.openshift.io/apply-label: cert-manager.io/v1/certificates/<namespace>/<name>,v1/secrets/<namespace>/<secret-name>
```

LCA then applies the `lca.openshift.io/backup` label to those resources, which tells Velero to include the raw data (including private keys) in the backup.

**Scripts available:**

| Script | Purpose |
|--------|---------|
| `scripts/ibu/label-cert-resources.sh` | Labels Certificate CRs and TLS Secrets, outputs the annotation value for the Backup CR |
| `scripts/ibu/run-ibu-preserved-test.sh` | End-to-end test that labels resources, simulates IBU, and validates preservation |

Or via Makefile:
```bash
make test-ibu-preserved  # Run the full preservation scenario
make test-ibu-both       # Run both scenarios (loss + preserved) for comparison
```

The labeling script auto-discovers all Certificate CRs in a namespace, finds their associated TLS Secrets, applies the labels, and outputs the exact annotation value customers would add to their Backup CR.

### How does the simulation differ from real LCA behavior?

The simulation does two things manually that LCA would do automatically:

1. **Manual labeling** - The script applies `lca.openshift.io/backup` labels directly to the certs/secrets
2. **Manual labelSelector** - The Backup CR uses `labelSelector` to pick up those labeled resources

From `backup-preserved.yaml`:
```yaml
# In real IBU, LCA applies these labels based on apply-label annotation
labelSelector:
  matchLabels:
    lca.openshift.io/backup: ${BACKUP_NAME}
```

**In a real IBU with LCA**, the customer workflow is simpler:

1. Add the `lca.openshift.io/apply-label` annotation to the Backup CR with the list of resources
2. LCA automatically:
   - Applies `lca.openshift.io/backup` labels to those resources
   - Adds the `labelSelector` to the Backup CR

Same end result - the scripts simulate LCA's behavior since the test environment doesn't have Lifecycle Agent running. The scripts output the `apply-label` annotation value so customers know what to put on their Backup CR for real IBU.

---

## References

- [IBU Certificate Loss Validation Report](https://gist.github.com/sebrandon1/71f33b35aea2aa4cf9edda855201c8fc)
- [IBU Testing Documentation](../IBU-TESTING.md)
- [Test Scripts](../scripts/ibu/)
