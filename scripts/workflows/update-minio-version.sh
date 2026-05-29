#!/bin/bash

################################################################################
# Script: update-minio-version.sh
# Description: Update MinIO version in deployment file
# Used by: check-minio-version.yml
################################################################################

set -euo pipefail

current="$1"
latest="$2"

sed -i "s|quay.io/minio/minio:${current}|quay.io/minio/minio:${latest}|" \
	yaml/ibu/minio/deployment.yaml

echo "Updated MinIO from $current to $latest"
