#!/usr/bin/env bats
# Guards against applying yaml/ templates without envsubst. No cluster required.

setup() {
	export CLUSTER_TYPE=kubernetes
	export KUBE_CLI=true
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export REPO_ROOT
	# shellcheck disable=SC1091
	source "$REPO_ROOT/lib/common.sh"
}

@test "no script applies a yaml/ manifest with raw apply -f" {
	run grep -rnE 'apply -f "?(\$\{?[A-Z_]*YAML_DIR|[^ ]*yaml/)' \
		"$REPO_ROOT/scripts" "$REPO_ROOT/lib" "$REPO_ROOT/Makefile"
	if [ "$status" -eq 0 ]; then
		echo "Use apply_yaml_template instead of raw apply -f:"
		echo "$output"
	fi
	[ "$status" -eq 1 ]
}

@test "MinIO deployment renders a concrete image tag" {
	export MINIO_VERSION=RELEASE.2025-09-07T16-13-09Z
	DRY_RUN=true run apply_yaml_template "$REPO_ROOT/yaml/ibu/minio/deployment.yaml" "MinIO deployment"
	[ "$status" -eq 0 ]
	[[ "$output" == *"image: quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z"* ]]
	[[ "$output" != *'${MINIO_VERSION}'* ]]
}

@test "IBU credential secrets render without placeholders" {
	export MINIO_ACCESS_KEY=minio MINIO_SECRET_KEY=minio123
	for f in yaml/ibu/minio/secret.yaml yaml/ibu/oadp/cloud-credentials-secret.yaml; do
		DRY_RUN=true run apply_yaml_template "$REPO_ROOT/$f" "secret"
		[ "$status" -eq 0 ]
		[[ "$output" != *'${'* ]]
	done
}
