#!/bin/bash

################################################################################
# Script: update-ubi9-python-version.sh
# Description: Update UBI9 Python 3.9 version in deployment file
# Used by: check-ubi9-python-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

sed -i "s|ubi9/python-39:${current}|ubi9/python-39:${latest}|" \
	yaml/fake-dns-api/deployment.yaml

echo "Updated UBI9 Python 3.9 from $current to $latest"
