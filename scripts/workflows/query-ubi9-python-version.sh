#!/bin/bash

################################################################################
# Script: query-ubi9-python-version.sh
# Description: Query Red Hat Pyxis API for latest UBI9 Python 3.9 version
# Used by: check-ubi9-python-version.yml
################################################################################

set -euo pipefail

tags=$(curl -sL "https://catalog.redhat.io/api/containers/v1/repositories/registry/registry.access.redhat.com/repository/ubi9/python-39/tags?page_size=100&page=0" |
	jq -r '.data[].name // empty')

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

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
