#!/bin/bash

################################################################################
# Script: query-acme-dns-version.sh
# Description: Query GitHub releases API for latest acme-dns version
# Used by: check-acme-dns-version.yml
################################################################################

set -euo pipefail

latest=$(curl -sL "https://api.github.com/repos/joohoi/acme-dns/releases/latest" |
	jq -r '.tag_name // empty')

if [ -z "$latest" ]; then
	echo "Failed to fetch latest acme-dns release from GitHub"
	exit 1
fi

echo "version=$latest" >>"$GITHUB_OUTPUT"
echo "Latest available version: $latest"
