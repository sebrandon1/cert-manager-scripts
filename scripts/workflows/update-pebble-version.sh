#!/bin/bash

################################################################################
# Script: update-pebble-version.sh
# Description: Update Pebble version across deployment files
# Used by: check-pebble-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

sed -i "s|ghcr.io/letsencrypt/pebble:${current}|ghcr.io/letsencrypt/pebble:${latest}|" \
	yaml/pebble/deployment.yaml

sed -i "s|ghcr.io/letsencrypt/pebble-challtestsrv:${current}|ghcr.io/letsencrypt/pebble-challtestsrv:${latest}|" \
	yaml/pebble-challtestsrv/deployment.yaml

echo "Updated Pebble from $current to $latest in both deployment files"
