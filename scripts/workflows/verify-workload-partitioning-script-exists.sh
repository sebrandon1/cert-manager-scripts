#!/bin/bash
################################################################################
# Script: verify-workload-partitioning-script-exists.sh
# Description: Verify that workload partitioning check script exists
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

if [ ! -f scripts/troubleshooting/check-workload-partitioning.sh ]; then
	echo "❌ Workload partitioning check script not found"
	exit 1
fi
echo "✅ Workload partitioning check script exists"
