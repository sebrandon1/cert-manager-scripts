#!/bin/bash

################################################################################
# Script: query-minio-version.sh
# Description: Query quay.io API for latest MinIO release tag
# Used by: check-minio-version.yml
################################################################################

set -euo pipefail

tags=$(curl -sL "https://quay.io/api/v1/repository/minio/minio/tag/?limit=100&onlyActiveTags=true" |
	jq -r '.tags[].name // empty')

if [ -z "$tags" ]; then
	echo "Failed to fetch tags from quay.io"
	exit 1
fi

latest=$(echo "$tags" | grep -E '^RELEASE\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$' | sort -r | head -1)

if [ -z "$latest" ]; then
	echo "No valid RELEASE tags found"
	echo "Raw tags:"
	echo "$tags" | head -20
	exit 1
fi

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
