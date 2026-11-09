#!/usr/bin/env bats
# Guards against make clean removing certificates this repo did not create.
# No cluster required.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "clean-certs selects by ownership instead of deleting whole resource types" {
	run grep -nE 'delete (certificates|certificaterequests|orders|challenges) --all' "$REPO_ROOT/Makefile"
	[ "$status" -eq 1 ]

	run make -n -C "$REPO_ROOT" clean-certs
	[ "$status" -eq 0 ]
	[[ "$output" == *'delete certificates -l app.kubernetes.io/managed-by=cert-manager-scripts'* ]]
}

@test "every Certificate manifest carries the ownership label" {
	local f failed=0
	while IFS= read -r f; do
		if ! grep -q 'app.kubernetes.io/managed-by: cert-manager-scripts' "$f"; then
			echo "missing ownership label: ${f#"$REPO_ROOT"/}"
			failed=1
		fi
	done < <(grep -rl 'kind: Certificate' "$REPO_ROOT/yaml")
	[ "$failed" -eq 0 ]
}
