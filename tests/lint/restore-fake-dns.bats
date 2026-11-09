#!/usr/bin/env bats
# Restoring the saved DNS configuration must not depend on a live cluster.
# No cluster required.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	STUB_DIR="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_DIR"
	export CALL_LOG="$BATS_TEST_TMPDIR/calls"
	: >"$CALL_LOG"

	cat >"$STUB_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CALL_LOG"
case "$1" in
get)
	if [[ "$2" == configmap && "${STUB_HAS_BACKUP:-0}" == 1 ]]; then
		case "$*" in
		*"jsonpath={.data.mode}"*) echo "${STUB_MODE:-}" ;;
		*"jsonpath={.data.servers"*) echo "${STUB_SERVERS:-null}" ;;
		*"jsonpath={.data.Corefile}"*) echo "${STUB_COREFILE:-}" ;;
		esac
		exit 0
	fi
	exit 1
	;;
*) exit 0 ;;
esac
EOF
	chmod +x "$STUB_DIR/kubectl"
}

run_restore() {
	run env CLUSTER_TYPE="${CLUSTER_TYPE:-kubernetes}" KUBE_CLI=kubectl \
		PATH="$STUB_DIR:$PATH" CALL_LOG="$CALL_LOG" "$@" \
		bash "$REPO_ROOT/scripts/restore-fake-dns.sh"
}

@test "no backup leaves CoreDNS untouched and exits 0" {
	run_restore CLUSTER_TYPE=kubernetes STUB_HAS_BACKUP=0
	[ "$status" -eq 0 ]
	[[ "$output" == *"No DNS backup found"* ]]
	run grep -E 'patch (dns|configmap)' "$CALL_LOG"
	[ "$status" -eq 1 ]
}

@test "OpenShift backup restores the saved servers array" {
	local servers='[{"name":"corp","zones":["corp.local"],"forwardPlugin":{"upstreams":["10.0.0.2:53"]}}]'
	run_restore CLUSTER_TYPE=openshift STUB_HAS_BACKUP=1 STUB_MODE=openshift STUB_SERVERS="$servers"
	[ "$status" -eq 0 ]
	grep -q 'patch dns.operator.openshift.io/default --type=merge' "$CALL_LOG"
	grep -q 'corp.local' "$CALL_LOG"
	run grep -F 'fake-dns-example' "$CALL_LOG"
	[ "$status" -eq 1 ]
	grep -q 'delete configmap fake-dns-backup -n default' "$CALL_LOG"
}

@test "Kubernetes backup restores the saved Corefile" {
	run_restore CLUSTER_TYPE=kubernetes STUB_HAS_BACKUP=1 STUB_MODE=kubernetes STUB_COREFILE='.:53 { forward . 8.8.8.8 }'
	[ "$status" -eq 0 ]
	grep -q 'patch configmap coredns -n kube-system --type=merge' "$CALL_LOG"
	grep -q 'Corefile' "$CALL_LOG"
}
