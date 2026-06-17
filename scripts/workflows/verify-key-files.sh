#!/bin/bash
################################################################################
# Script: verify-key-files.sh
# Description: Verify that required repository files exist (README, Makefile, etc.)
################################################################################

set -euo pipefail

echo "Checking for key files..."
KEY_FILES=(
	"README.md"
	"Makefile"
	"CONTRIBUTING.md"
	"docs/troubleshooting.md"
)

EXIT_CODE=0
for file in "${KEY_FILES[@]}"; do
	if [ -f "$file" ]; then
		echo "✅ File exists: $file"
	else
		echo "❌ Required file missing: $file"
		EXIT_CODE=1
	fi
done
exit $EXIT_CODE
