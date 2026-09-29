#!/usr/bin/env bats
# Unit tests for lib/common.sh. No cluster required.
# Source common.sh after CLUSTER_TYPE/KUBE_CLI so detect_cluster_type is skipped.

setup() {
	export CLUSTER_TYPE=kubernetes
	export KUBE_CLI=true
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	# shellcheck disable=SC1091
	source "$REPO_ROOT/lib/common.sh"
}

pem_b64() {
	printf '%s\n' "$1" | base64
}

counted_predicate() {
	local count
	count=$(<"$COUNTER_FILE")
	count=$((count + 1))
	printf '%s\n' "$count" >"$COUNTER_FILE"
	[[ $count -ge $1 ]]
}

@test "get_key_pem_type detects EC PRIVATE KEY" {
	run get_key_pem_type "$(pem_b64 '-----BEGIN EC PRIVATE KEY-----')"
	[ "$status" -eq 0 ]
	[ "$output" = "EC PRIVATE KEY" ]
}

@test "get_key_pem_type detects RSA PRIVATE KEY" {
	run get_key_pem_type "$(pem_b64 '-----BEGIN RSA PRIVATE KEY-----')"
	[ "$status" -eq 0 ]
	[ "$output" = "RSA PRIVATE KEY" ]
}

@test "get_key_pem_type detects PKCS#8 PRIVATE KEY" {
	run get_key_pem_type "$(pem_b64 '-----BEGIN PRIVATE KEY-----')"
	[ "$status" -eq 0 ]
	[ "$output" = "PRIVATE KEY" ]
}

@test "get_key_pem_type returns UNKNOWN for empty input" {
	run get_key_pem_type ""
	[ "$status" -eq 0 ]
	[ "$output" = "UNKNOWN" ]
}

@test "get_key_pem_type returns UNKNOWN for garbage" {
	run get_key_pem_type "$(pem_b64 'not a pem header')"
	[ "$status" -eq 0 ]
	[ "$output" = "UNKNOWN" ]
}

@test "log_info is silent when LOG_LEVEL=quiet" {
	run bash -c '
		export LOG_LEVEL=quiet CLUSTER_TYPE=kubernetes KUBE_CLI=true
		# shellcheck disable=SC1091
		source "$1/lib/common.sh"
		log_info "should not appear"
	' _ "$REPO_ROOT"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "log_error still prints when LOG_LEVEL=error" {
	run bash -c '
		export LOG_LEVEL=error CLUSTER_TYPE=kubernetes KUBE_CLI=true
		# shellcheck disable=SC1091
		source "$1/lib/common.sh"
		log_error "boom"
	' _ "$REPO_ROOT"
	[ "$status" -eq 0 ]
	[[ "$output" == *"[ERROR]"* ]]
	[[ "$output" == *"boom"* ]]
}

@test "apply_yaml_template fails when the file is missing" {
	run apply_yaml_template "$REPO_ROOT/tests/fixtures/does-not-exist.yaml" ConfigMap
	[ "$status" -ne 0 ]
	[[ "$output" == *"not found"* ]]
}

@test "apply_yaml_template DRY_RUN prints substituted YAML without kube" {
	export DRY_RUN=true
	export FOO=unit-test-cm
	run apply_yaml_template "$REPO_ROOT/tests/fixtures/sample-configmap.yaml" ConfigMap
	[ "$status" -eq 0 ]
	[[ "$output" == *"name: unit-test-cm"* ]]
	[[ "$output" != *'${FOO}'* ]]
}

@test "require_cmd succeeds for an existing binary" {
	run require_cmd bash
	[ "$status" -eq 0 ]
}

@test "require_cmd exits 1 for a missing binary" {
	run require_cmd definitely_not_a_real_binary_xyzzy
	[ "$status" -eq 1 ]
	[[ "$output" == *"definitely_not_a_real_binary_xyzzy"* ]]
}

@test "_parse_duration_seconds accepts a bare number" {
	run _parse_duration_seconds 300
	[ "$status" -eq 0 ]
	[ "$output" = 300 ]
}

@test "_parse_duration_seconds converts seconds" {
	run _parse_duration_seconds 15s
	[ "$status" -eq 0 ]
	[ "$output" = 15 ]
}

@test "_parse_duration_seconds converts minutes" {
	run _parse_duration_seconds 5m
	[ "$status" -eq 0 ]
	[ "$output" = 300 ]
}

@test "_parse_duration_seconds converts hours" {
	run _parse_duration_seconds 2h
	[ "$status" -eq 0 ]
	[ "$output" = 7200 ]
}

@test "_parse_duration_seconds rejects unknown formats" {
	run _parse_duration_seconds 1d
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "build_lca_annotations includes certificates and existing secrets" {
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	cat >"$BATS_TEST_TMPDIR/bin/oc" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
	"get certificates")
		[[ "$3" == -n && "$4" == test-ns ]] || exit 1
		printf 'cert-a\ncert-b\n'
		;;
	"get certificate")
		[[ "$4" == -n && "$5" == test-ns ]] || exit 1
		printf 'secret-%s\n' "${3#cert-}"
		;;
	"get secret")
		[[ "$4" == -n && "$5" == test-ns && "$3" == secret-a ]]
		;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/oc"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

	run build_lca_annotations test-ns
	[ "$status" -eq 0 ]
	[ "$output" = "cert-manager.io/v1/certificates/test-ns/cert-a,v1/secrets/test-ns/secret-a,cert-manager.io/v1/certificates/test-ns/cert-b" ]
}

@test "check_help prints the calling script header for -h and --help" {
	cat >"$BATS_TEST_TMPDIR/help-script.sh" <<'EOF'
#!/usr/bin/env bash
##
# Example help text
##
source "$REPO_ROOT/lib/common.sh"
check_help "$@"
EOF
	for flag in -h --help; do
		run bash "$BATS_TEST_TMPDIR/help-script.sh" "$flag"
		[ "$status" -eq 0 ]
		[ "$output" = "Example help text" ]
	done
}

@test "print_summary displays labels and values" {
	run print_summary Cluster ready Namespace test-ns
	[ "$status" -eq 0 ]
	[[ "$output" == *"SUMMARY"* ]]
	[[ "$output" == *"Cluster:"*"ready"* ]]
	[[ "$output" == *"Namespace:"*"test-ns"* ]]
}

@test "print_header displays the requested title" {
	run print_header "Unit checks"
	[ "$status" -eq 0 ]
	[[ "$output" == *"========================================"* ]]
	[[ "$output" == *"Unit checks"* ]]
}

@test "confirm succeeds with SKIP_CONFIRM without reading stdin" {
	export SKIP_CONFIRM=1
	run bash -c 'source "$1/lib/common.sh"; confirm "Proceed?" </dev/null' _ "$REPO_ROOT"
	[ "$status" -eq 0 ]
}

@test "require_exported_vars reports an unset template variable" {
	printf 'name: ${UNIT_TEST_MISSING}\n' >"$BATS_TEST_TMPDIR/template.yaml"
	unset UNIT_TEST_MISSING
	run require_exported_vars "$BATS_TEST_TMPDIR/template.yaml"
	[ "$status" -eq 1 ]
	[[ "$output" == *"UNIT_TEST_MISSING"* ]]
}

@test "require_exported_vars accepts a set but empty variable" {
	printf 'name: $UNIT_TEST_PRESENT\n' >"$BATS_TEST_TMPDIR/template.yaml"
	export UNIT_TEST_PRESENT=""
	run require_exported_vars "$BATS_TEST_TMPDIR/template.yaml"
	[ "$status" -eq 0 ]
}

@test "retry succeeds on the first attempt" {
	COUNTER_FILE="$BATS_TEST_TMPDIR/attempts"
	printf '0\n' >"$COUNTER_FILE"
	run retry 3 0 counted_predicate 1
	[ "$status" -eq 0 ]
	[ "$(<"$COUNTER_FILE")" -eq 1 ]
}

@test "retry succeeds after transient failures" {
	COUNTER_FILE="$BATS_TEST_TMPDIR/attempts"
	printf '0\n' >"$COUNTER_FILE"
	run retry 3 0 counted_predicate 3
	[ "$status" -eq 0 ]
	[ "$(<"$COUNTER_FILE")" -eq 3 ]
}

@test "retry fails after exhausting attempts" {
	COUNTER_FILE="$BATS_TEST_TMPDIR/attempts"
	printf '0\n' >"$COUNTER_FILE"
	run retry 3 0 counted_predicate 4
	[ "$status" -eq 1 ]
	[ "$(<"$COUNTER_FILE")" -eq 3 ]
	[[ "$output" == *"failed after 3 attempts"* ]]
}

@test "wait_for_condition succeeds when the predicate becomes true" {
	COUNTER_FILE="$BATS_TEST_TMPDIR/attempts"
	printf '0\n' >"$COUNTER_FILE"
	run wait_for_condition 3 0 counted_predicate 2
	[ "$status" -eq 0 ]
	[ "$(<"$COUNTER_FILE")" -eq 2 ]
}

@test "wait_for_condition fails after exhausting attempts" {
	COUNTER_FILE="$BATS_TEST_TMPDIR/attempts"
	printf '0\n' >"$COUNTER_FILE"
	run wait_for_condition 3 0 counted_predicate 4
	[ "$status" -eq 1 ]
	[ "$(<"$COUNTER_FILE")" -eq 3 ]
}
