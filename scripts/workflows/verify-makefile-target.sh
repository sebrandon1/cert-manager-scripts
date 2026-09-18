#!/bin/bash
################################################################################
# Script: verify-makefile-target.sh
# Description: Verify that check-workload-partitioning target exists in Makefile
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

if ! grep -q "check-workload-partitioning:" Makefile; then
	echo "❌ check-workload-partitioning target not found in Makefile"
	exit 1
fi
echo "✅ Makefile target exists"
