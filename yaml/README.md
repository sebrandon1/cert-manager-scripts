# YAML Manifests

Kubernetes/OpenShift templates, grouped by component. Placeholders use `${VARIABLE}` and are substituted at apply time by `apply_yaml_template` in `lib/common.sh` (envsubst + `oc apply`).

## Structure

| Directory | Description | Files |
|-----------|-------------|-------|
| [`acme-dns/`](acme-dns/) | acme-dns server for DNS-01 | 4 |
| [`cert-manager-operator/`](cert-manager-operator/) | OpenShift cert-manager operator install | 2 |
| [`certificates/`](certificates/) | Test certificate templates | 2 |
| [`fake-dns-api/`](fake-dns-api/) | Air-gapped RFC2136 DNS server | 5 |
| [`ingress-test/`](ingress-test/) | Route/Ingress TLS integration test | 4 |
| [`issuers/`](issuers/) | ClusterIssuers (HTTP-01, DNS-01, CA, self-signed) | 6 |
| [`monitoring/`](monitoring/) | ServiceMonitor and PrometheusRule | 2 |
| [`pebble/`](pebble/) | Pebble ACME test server | 5 |
| [`pebble-challtestsrv/`](pebble-challtestsrv/) | Pebble challenge test server | 2 |
| [`ibu/`](ibu/) | IBU testing (MinIO, OADP, backups) | 3 subdirs |

Each subdirectory has a README except `ingress-test/` and `monitoring/` — those are applied by `make test-ingress-tls` and `make install-monitoring`.

## Adding manifests

1. Put files in the matching subdirectory (or add one).
2. Use `${VARIABLE}` for anything callers should override.
3. Export the variables in the install script (`export VAR="${VAR:-default}"`).
4. Apply with `apply_yaml_template "$YAML_DIR/file.yaml" "ResourceType"` — do not pipe envsubst inline.
