#!/bin/bash

################################################################################
# Script: query-version.sh
# Description: Query upstream APIs for the latest version of a component
# Usage: query-version.sh <component>
# Components: pebble, acme-dns, operator, minio, ubi9-python
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

component="${1:-}"

if [ -z "$component" ]; then
	echo "Usage: $0 <component>"
	echo "Components: pebble, acme-dns, operator, minio, ubi9-python"
	exit 1
fi

query_github_latest() {
	local repo="$1" label="$2"
	latest=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest" |
		jq -r '.tag_name // empty')
	if [ -z "$latest" ]; then
		echo "Failed to fetch latest ${label} release from GitHub"
		exit 1
	fi
}

case "$component" in
pebble)
	query_github_latest "letsencrypt/pebble" "Pebble"
	latest="${latest#v}"
	;;

acme-dns)
	query_github_latest "joohoi/acme-dns" "acme-dns"
	;;

operator)
	tags=$(curl -sL "https://catalog.redhat.com/api/containers/v1/images?filter=repositories.repository==cert-manager/cert-manager-operator-rhel9" |
		jq -r '[.data[].repositories[0].tags[].name] | unique[]')
	if [ -z "$tags" ]; then
		echo "Failed to fetch tags from Red Hat catalog API"
		exit 1
	fi
	latest=$(echo "$tags" | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
	if [ -z "$latest" ]; then
		echo "No valid version tags found"
		echo "Raw tags:"
		echo "$tags" | head -20
		exit 1
	fi
	;;

minio)
	# Quay's v1 tag endpoint requires authentication; MinIO publishes the same RELEASE tags publicly on GitHub.
	tags=$(curl -fsSL "https://api.github.com/repos/minio/minio/tags?per_page=100" |
		jq -r 'if type == "array" then .[].name // empty else empty end')
	if [ -z "$tags" ]; then
		echo "Failed to fetch MinIO release tags from GitHub"
		exit 1
	fi
	latest=$(echo "$tags" | grep -E '^RELEASE\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$' | sort -r | head -1)
	if [ -z "$latest" ]; then
		echo "No valid MinIO RELEASE tags found"
		echo "Raw tags:"
		echo "$tags" | head -20
		exit 1
	fi
	;;

ubi9-python)
	tags=$(curl -sL "https://catalog.redhat.com/api/containers/v1/images?filter=repositories.repository==ubi9/python-39" |
		jq -r '[.data[].repositories[0].tags[].name] | unique[]')
	if [ -z "$tags" ]; then
		echo "Failed to fetch tags from Red Hat catalog API"
		exit 1
	fi
	latest=$(echo "$tags" | grep -oE '^[0-9]+\.[0-9]+$' | sort -V | tail -1)
	if [ -z "$latest" ]; then
		echo "No valid version tags found"
		echo "Raw tags:"
		echo "$tags" | head -20
		exit 1
	fi
	;;

*)
	echo "Unknown component: $component"
	echo "Valid components: pebble, acme-dns, operator, minio, ubi9-python"
	exit 1
	;;
esac

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
