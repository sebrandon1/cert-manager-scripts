#!/bin/bash
################################################################################
# Script: run-workload-partitioning-check.sh
# Description: Execute the workload partitioning check via Makefile target
################################################################################

set -euo pipefail

echo "=== Workload Partitioning Check ==="
make check-workload-partitioning
