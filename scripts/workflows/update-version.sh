#!/bin/bash

################################################################################
# Script: update-version.sh
# Description: Update a component's version across repo files
# Usage: update-version.sh <component> <current_version> <latest_version>
# Components: pebble, acme-dns, operator, minio, ubi9-python
################################################################################

set -euo pipefail

component="${1:-}"
current="${2:-}"
latest="${3:-}"

if [ -z "$component" ] || [ -z "$current" ] || [ -z "$latest" ]; then
	echo "Usage: $0 <component> <current_version> <latest_version>"
	exit 1
fi

case "$component" in
pebble)
	sed -i "s|ghcr.io/letsencrypt/pebble:${current}|ghcr.io/letsencrypt/pebble:${latest}|" \
		yaml/pebble/deployment.yaml
	sed -i "s|ghcr.io/letsencrypt/pebble-challtestsrv:${current}|ghcr.io/letsencrypt/pebble-challtestsrv:${latest}|" \
		yaml/pebble-challtestsrv/deployment.yaml
	echo "Updated Pebble from $current to $latest in both deployment files"
	;;

acme-dns)
	sed -i "s|joohoi/acme-dns:${current}|joohoi/acme-dns:${latest}|" \
		yaml/acme-dns/deployment.yaml
	echo "Updated acme-dns from $current to $latest"
	;;

operator)
	sed -i "s/CERT_MANAGER_VERSION:-${current}/CERT_MANAGER_VERSION:-${latest}/" \
		scripts/install-cert-manager-operator.sh
	sed -i "s/CERT_MANAGER_VERSION=${current}/CERT_MANAGER_VERSION=${latest}/" \
		.env.example
	sed -i "s/\`${current}\`/\`${latest}\`/" CLAUDE.md
	sed -i "s/${current}/${latest}/" \
		.github/workflows/nightly.yml
	echo "Updated default version from $current to $latest"
	;;

minio)
	sed -i "s|quay.io/minio/minio:${current}|quay.io/minio/minio:${latest}|" \
		yaml/ibu/minio/deployment.yaml
	echo "Updated MinIO from $current to $latest"
	;;

ubi9-python)
	sed -i "s|ubi9/python-39:${current}|ubi9/python-39:${latest}|" \
		yaml/fake-dns-api/deployment.yaml
	echo "Updated UBI9 Python 3.9 from $current to $latest"
	;;

*)
	echo "Unknown component: $component"
	echo "Valid components: pebble, acme-dns, operator, minio, ubi9-python"
	exit 1
	;;
esac
