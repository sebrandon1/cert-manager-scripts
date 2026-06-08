#!/bin/bash

################################################################################
# Script: query-operator-version.sh
# Description: Query Red Hat Pyxis API for latest cert-manager operator version
# Used by: check-operator-version.yml
################################################################################

set -euo pipefail

tags=$(curl -s "https://catalog.redhat.com/api/containers/v1/images?filter=repositories.repository==cert-manager/cert-manager-operator-rhel9&page_size=50&sort_by=creation_date%5Bdesc%5D" |
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

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
