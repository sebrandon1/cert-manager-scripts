#!/bin/bash
################################################################################
# Script: verify-script-references.sh
# Description: Validate cross-references between scripts, docs, and Makefile
################################################################################

set -euo pipefail

FAILURES=0

# 1. Verify all make target references in docs point to real Makefile targets
echo "Checking make target references in documentation..."
MAKEFILE_TARGETS=$(grep -oE '^[a-z][a-z0-9_-]*:' Makefile | sed 's/://')
DOC_REFS=$(grep -roh 'make [a-z][a-z0-9_-]*' docs/ guide/ README.md 2>/dev/null | sed 's/make //' | sort -u)

while IFS= read -r ref; do
	[[ -z "$ref" ]] && continue
	if ! echo "$MAKEFILE_TARGETS" | grep -qx "$ref"; then
		echo "❌ docs reference non-existent target: make $ref"
		FAILURES=$((FAILURES + 1))
	fi
done <<<"$DOC_REFS"
if [ "$FAILURES" -eq 0 ]; then
	echo "✅ All make target references in docs are valid"
fi

# 2. Verify script file references in code
echo ""
echo "Checking script file references in code..."
BEFORE=$FAILURES
while IFS= read -r line; do
	file=$(echo "$line" | cut -d: -f1)
	ref=$(echo "$line" | grep -oE '\./scripts/[a-zA-Z0-9/_-]+\.sh')
	if [ ! -f "$ref" ]; then
		echo "❌ $file references non-existent script: $ref"
		FAILURES=$((FAILURES + 1))
	fi
done < <(grep -rn '\./scripts/[a-zA-Z0-9/_-]*\.sh' scripts/ Makefile --include="*.sh" 2>/dev/null || true)
if [ "$FAILURES" -eq "$BEFORE" ]; then
	echo "✅ All script file references are valid"
fi

# 3. Verify source paths resolve correctly
echo ""
echo "Checking source path resolution..."
BEFORE=$FAILURES
while IFS= read -r file; do
	dir=$(dirname "$file")

	script_dir_def=$(grep -m1 'SCRIPT_DIR=' "$file" 2>/dev/null || true)
	[ -z "$script_dir_def" ] && continue

	if [[ "$script_dir_def" == *"/.."* ]]; then
		effective_dir="$dir/.."
	else
		effective_dir="$dir"
	fi

	src_rel=$(grep -m1 '^source ' "$file" 2>/dev/null || true)
	# shellcheck disable=SC2016
	src_rel=$(echo "$src_rel" | grep -oE '\$SCRIPT_DIR/[^"]+' || true)
	[ -z "$src_rel" ] && continue

	resolved="${src_rel/\$SCRIPT_DIR/$effective_dir}"
	if [ ! -f "$resolved" ]; then
		echo "❌ $file sources non-existent file: $src_rel"
		FAILURES=$((FAILURES + 1))
	fi
done < <(find scripts/ lib/ -name "*.sh" -type f)
if [ "$FAILURES" -eq "$BEFORE" ]; then
	echo "✅ All source paths resolve correctly"
fi

# 4. Bash syntax check on all scripts
echo ""
echo "Checking bash syntax on all scripts..."
BEFORE=$FAILURES
while IFS= read -r script; do
	if ! bash -n "$script" 2>/dev/null; then
		echo "❌ Syntax error in: $script"
		FAILURES=$((FAILURES + 1))
	fi
done < <(find scripts/ lib/ -name "*.sh" -type f)
if [ "$FAILURES" -eq "$BEFORE" ]; then
	echo "✅ All scripts pass syntax check"
fi

# 5. Verify all scripts are executable
echo ""
echo "Checking script permissions..."
BEFORE=$FAILURES
while IFS= read -r script; do
	if [ ! -x "$script" ]; then
		echo "❌ Script not executable: $script"
		FAILURES=$((FAILURES + 1))
	fi
done < <(find scripts/ -name "*.sh" -type f)
if [ "$FAILURES" -eq "$BEFORE" ]; then
	echo "✅ All scripts are executable"
fi

# 6. Verify Makefile script references exist
echo ""
echo "Checking Makefile script references..."
BEFORE=$FAILURES
while IFS= read -r ref; do
	if [ ! -f "$ref" ]; then
		echo "❌ Makefile references non-existent script: $ref"
		FAILURES=$((FAILURES + 1))
	fi
done < <(grep -oE 'scripts/[a-zA-Z0-9/_-]+\.sh' Makefile | sort -u)
if [ "$FAILURES" -eq "$BEFORE" ]; then
	echo "✅ All Makefile script references are valid"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
	echo "❌ Found $FAILURES reference error(s)"
	exit 1
fi
echo "✅ All reference checks passed"
