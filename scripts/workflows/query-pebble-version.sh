#!/bin/bash

################################################################################
# Script: query-pebble-version.sh
# Description: Query GitHub releases API for latest Pebble version
# Used by: check-pebble-version.yml
################################################################################

set -euo pipefail

latest=$(curl -sL "https://api.github.com/repos/letsencrypt/pebble/releases/latest" |
	jq -r '.tag_name // empty')

if [ -z "$latest" ]; then
	echo "Failed to fetch latest Pebble release from GitHub"
	exit 1
fi

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
