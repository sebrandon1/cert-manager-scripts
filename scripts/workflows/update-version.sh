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
	sed -i "s|PEBBLE_VERSION:-${current}|PEBBLE_VERSION:-${latest}|" \
		scripts/install-pebble.sh
	sed -i "s|PEBBLE_CHALLTESTSRV_VERSION:-v${current}|PEBBLE_CHALLTESTSRV_VERSION:-v${latest}|" \
		scripts/install-pebble-challtestsrv.sh
	echo "Updated Pebble from $current to $latest in both install scripts"
	;;

acme-dns)
	sed -i "s|ACMEDNS_VERSION:-${current}|ACMEDNS_VERSION:-${latest}|" \
		scripts/install-local-dns.sh
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
	sed -i "s|MINIO_VERSION:-${current}|MINIO_VERSION:-${latest}|" \
		scripts/ibu/install-minio.sh
	echo "Updated MinIO from $current to $latest"
	;;

ubi9-python)
	sed -i "s|UBI9_PYTHON_VERSION:-${current}|UBI9_PYTHON_VERSION:-${latest}|" \
		scripts/install-fake-dns.sh
	echo "Updated UBI9 Python 3.9 from $current to $latest"
	;;

*)
	echo "Unknown component: $component"
	echo "Valid components: pebble, acme-dns, operator, minio, ubi9-python"
	exit 1
	;;
esac
