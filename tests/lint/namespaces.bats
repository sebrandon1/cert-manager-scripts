#!/usr/bin/env bats
# Guards against namespace literals creeping back into scripts. A literal here
# means a renamed component namespace works in the installer but not at runtime.
# No cluster required.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "scripts and lib do not hardcode component namespaces" {
	run bash -c 'find "$1/lib" "$1/scripts" -type f -name "*.sh" \
		-exec grep -nE -- "-n (cert-manager|pebble|fake-dns|acme-dns|minio|openshift-adp|default|ingress-tls-test)([^a-z-]|$)" {} + || true' \
		_ "$REPO_ROOT"
	if [ -n "$output" ]; then
		echo "Use the namespace variable (e.g. \"\${CERT_MANAGER_NAMESPACE:-cert-manager}\"):"
		echo "$output"
	fi
	[ -z "$output" ]
}
