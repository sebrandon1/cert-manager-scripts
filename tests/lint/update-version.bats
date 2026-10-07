#!/usr/bin/env bats
# Runs the operator version bump against a scratch copy of the repo files it
# edits, so a new hardcoded default cannot be left behind. No cluster required.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WORK="$BATS_TEST_TMPDIR/repo"
	FILES=(
		scripts/install-cert-manager-operator.sh
		scripts/workflows/check-olm-operator-bundle.sh
		.env.example
		CLAUDE.md
		docs/installation.md
		docs/getting-started.md
		yaml/cert-manager-operator/README.md
	)
	for f in "${FILES[@]}"; do
		mkdir -p "$WORK/$(dirname "$f")"
		cp "$REPO_ROOT/$f" "$WORK/$f"
	done
	CURRENT=$(grep -oE 'CERT_MANAGER_VERSION:-v[0-9]+\.[0-9]+\.[0-9]+' \
		"$REPO_ROOT/scripts/install-cert-manager-operator.sh" | cut -d- -f2)
}

@test "operator bump updates every documented default" {
	cd "$WORK"
	CLUSTER_TYPE=kubernetes KUBE_CLI=true run "$REPO_ROOT/scripts/workflows/update-version.sh" operator "$CURRENT" v9.98.7
	[ "$status" -eq 0 ]

	# file|pattern for each documented *default* (examples and the CI matrix
	# may legitimately name other versions).
	local defaults=(
		'scripts/install-cert-manager-operator.sh|CERT_MANAGER_VERSION:-%s'
		'scripts/workflows/check-olm-operator-bundle.sh|CERT_MANAGER_VERSION:-%s'
		'.env.example|CERT_MANAGER_VERSION=%s'
		'CLAUDE.md|| `CERT_MANAGER_VERSION` | `%s` |'
		'docs/installation.md|(default: `%s`)'
		'docs/getting-started.md|(default: `%s`)'
		'yaml/cert-manager-operator/README.md|CERT_MANAGER_VERSION="%s"'
		'yaml/cert-manager-operator/README.md|| `CERT_MANAGER_VERSION` | `%s` |'
	)
	local entry file pattern
	for entry in "${defaults[@]}"; do
		file="${entry%%|*}"
		pattern="${entry#*|}"
		# shellcheck disable=SC2059
		if grep -nF -- "$(printf "$pattern" "$CURRENT")" "$file"; then
			echo "$file still defaults to $CURRENT"
			return 1
		fi
		# shellcheck disable=SC2059
		grep -qF -- "$(printf "$pattern" v9.98.7)" "$file" || {
			echo "$file has no default matching: $pattern"
			return 1
		}
	done

	grep -qF 'export CHANNEL="stable-v9.98"' yaml/cert-manager-operator/README.md
}
