#!/bin/bash

################################################################################
# Script: update-operator-version.sh
# Description: Update cert-manager operator version across repo files
# Used by: check-operator-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

sed -i "s/CERT_MANAGER_VERSION:-${current}/CERT_MANAGER_VERSION:-${latest}/" \
	scripts/install-cert-manager-operator.sh

sed -i "s/CERT_MANAGER_VERSION=${current}/CERT_MANAGER_VERSION=${latest}/" \
	.env.example

sed -i "s/\`${current}\`/\`${latest}\`/" CLAUDE.md

sed -i "s/${current}/${latest}/" \
	.github/workflows/nightly.yml

echo "Updated default version from $current to $latest"
