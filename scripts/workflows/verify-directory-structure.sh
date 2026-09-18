#!/bin/bash
################################################################################
# Script: verify-directory-structure.sh
# Description: Verify that required repository directories exist
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

echo "Checking repository structure..."
REQUIRED_DIRS=(
	"scripts"
	"scripts/troubleshooting"
	"yaml"
	"docs"
)

EXIT_CODE=0
for dir in "${REQUIRED_DIRS[@]}"; do
	if [ -d "$dir" ]; then
		echo "✅ Directory exists: $dir"
	else
		echo "❌ Required directory missing: $dir"
		EXIT_CODE=1
	fi
done
exit $EXIT_CODE
