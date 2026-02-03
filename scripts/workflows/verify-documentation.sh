#!/bin/bash
################################################################################
# Script: verify-documentation.sh
# Description: Verify that workload partitioning is documented in markdown files
################################################################################

set -euo pipefail

echo "Checking for workload partitioning documentation..."
if grep -r "workload partitioning" . --include="*.md" >/dev/null; then
	echo "✅ Workload partitioning is documented"
	grep -r "workload partitioning" . --include="*.md" -l
else
	echo "⚠️  Warning: No documentation found mentioning workload partitioning"
fi
