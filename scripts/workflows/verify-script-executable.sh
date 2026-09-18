#!/bin/bash
################################################################################
# Script: verify-script-executable.sh
# Description: Verify that workload partitioning check script is executable
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

if [ ! -x scripts/troubleshooting/check-workload-partitioning.sh ]; then
	echo "❌ Workload partitioning check script is not executable"
	exit 1
fi
echo "✅ Workload partitioning check script is executable"
