#!/bin/bash

################################################################################
# Script: update-acme-dns-version.sh
# Description: Update acme-dns version in deployment file
# Used by: check-acme-dns-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

sed -i "s|joohoi/acme-dns:${current}|joohoi/acme-dns:${latest}|" \
	yaml/acme-dns/deployment.yaml

echo "Updated acme-dns from $current to $latest"
