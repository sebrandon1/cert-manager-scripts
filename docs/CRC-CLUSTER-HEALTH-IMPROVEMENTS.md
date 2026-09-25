# CI Cluster Health Checks

Integration tests deploy a CRC cluster. These scripts catch DNS/API instability before it looks like a cert-manager failure.

| Script | Role |
|--------|------|
| `scripts/workflows/verify-cluster-access.sh` | DNS, kubeconfig, auth, API reachability, node readiness, operator health |
| `scripts/workflows/recover-cluster.sh` | Retry DNS/auth/API after a transient failure |
| `scripts/workflows/display-component-status.sh` | Component status that degrades cleanly if the cluster is down |
| `scripts/workflows/wait-for-cluster-operators.sh` | Wait for cluster operators after CRC comes up |
| `scripts/workflows/install-ibu-prereqs-with-retry.sh` | Retry IBU prerequisite installation once after recovery and access verification |

Used from `.github/workflows/reusable-integration-test.yml`:

1. After CRC deploy: wait for operators, then health-check with retries.
2. Install the cert-manager operator in its own step. Wait up to five minutes for the selected CSV and retry once only while OLM has no terminal failure; require the controller deployment to become available and print OLM diagnostics on failure.
3. Run HTTP-01 retries after operator readiness, skipping operator installation in each retry. The API-server certificate step fails if cluster access is lost, allowing its retry hook to call `recover-cluster.sh`.
4. For IBU runs, retry prerequisite installation once after `recover-cluster.sh` and a cluster-access check. If access remains down, print cluster diagnostics and fail without restarting CRC.
5. Always: final health-check and component status (including on failure).
