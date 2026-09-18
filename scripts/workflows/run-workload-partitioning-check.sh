#!/bin/bash
################################################################################
# Script: run-workload-partitioning-check.sh
# Description: Execute the workload partitioning check via Makefile target
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

echo "=== Workload Partitioning Check ==="
make check-workload-partitioning
