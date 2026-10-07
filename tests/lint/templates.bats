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

@test "MinIO deployment renders the configured image" {
	export MINIO_IMAGE=image-registry.openshift-image-registry.svc:5000/minio/minio:RELEASE.2025-10-15T17-29-55Z
	DRY_RUN=true run apply_yaml_template "$REPO_ROOT/yaml/ibu/minio/deployment.yaml" "MinIO deployment"
	[ "$status" -eq 0 ]
	[[ "$output" == *"image: $MINIO_IMAGE"* ]]
	[[ "$output" != *'${'* ]]
}

@test "MinIO BuildConfig renders pinned source tags from public base images" {
	export MINIO_VERSION=RELEASE.2025-10-15T17-29-55Z MINIO_MC_VERSION=RELEASE.2025-08-13T08-35-41Z
	DRY_RUN=true run apply_yaml_template "$REPO_ROOT/yaml/ibu/minio/buildconfig.yaml" "MinIO BuildConfig"
	[ "$status" -eq 0 ]
	[[ "$output" == *"--branch RELEASE.2025-10-15T17-29-55Z https://github.com/minio/minio.git"* ]]
	[[ "$output" == *"--branch RELEASE.2025-08-13T08-35-41Z https://github.com/minio/mc.git"* ]]
	[[ "$output" == *"name: minio:RELEASE.2025-10-15T17-29-55Z"* ]]
	[[ "$output" != *'${'* ]]
	local from_lines public_from_lines
	from_lines=$(grep -cE '^ +FROM ' <<<"$output")
	public_from_lines=$(grep -cE '^ +FROM registry\.access\.redhat\.com/' <<<"$output")
	[ "$from_lines" -eq 2 ]
	[ "$public_from_lines" -eq 2 ]
}

@test "nothing references the unpublished quay.io/minio images" {
	run grep -rn 'quay.io/minio' "$REPO_ROOT/scripts" "$REPO_ROOT/yaml" "$REPO_ROOT/.github" "$REPO_ROOT/lib"
	[ "$status" -eq 1 ]
}

@test "IBU credential secrets render without placeholders" {
	export MINIO_ACCESS_KEY=minio MINIO_SECRET_KEY=minio123
	for f in yaml/ibu/minio/secret.yaml yaml/ibu/oadp/cloud-credentials-secret.yaml; do
		DRY_RUN=true run apply_yaml_template "$REPO_ROOT/$f" "secret"
		[ "$status" -eq 0 ]
		[[ "$output" != *'${'* ]]
	done
}
