#!/bin/bash

################################################################################
# Script: compare-versions.sh
# Description: Compare two semver versions and set needs_update output
# Used by: check-operator-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

echo "Current: $current"
echo "Latest:  $latest"

if [ "$current" = "$latest" ]; then
	echo "Already on the latest version"
	echo "needs_update=false" >>"$GITHUB_OUTPUT"
else
	newer=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)
	if [ "$newer" = "$latest" ]; then
		echo "New version available: $latest (current: $current)"
		echo "needs_update=true" >>"$GITHUB_OUTPUT"
	else
		echo "Latest ($latest) is not newer than current ($current)"
		echo "needs_update=false" >>"$GITHUB_OUTPUT"
	fi
fi
