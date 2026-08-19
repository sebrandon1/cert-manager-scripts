# CI Cluster Health Checks

Integration tests deploy a CRC cluster. These scripts catch DNS/API instability before it looks like a cert-manager failure.

| Script | Role |
|--------|------|
| `scripts/workflows/verify-cluster-access.sh` | DNS, kubeconfig, auth, API reachability, node readiness, operator health |
| `scripts/workflows/recover-cluster.sh` | Retry DNS/auth/API after a transient failure |
| `scripts/workflows/display-component-status.sh` | Component status that degrades cleanly if the cluster is down |
| `scripts/workflows/wait-for-cluster-operators.sh` | Wait for cluster operators after CRC comes up |

Used from `.github/workflows/reusable-integration-test.yml`:

1. After CRC deploy: wait for operators, then health-check with retries.
2. Before HTTP-01 and API-server cert tests: health-check again.
3. On test failure: run `recover-cluster.sh` before retry.
4. Always: final health-check and component status (including on failure).
