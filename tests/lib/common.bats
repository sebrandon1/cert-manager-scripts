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
