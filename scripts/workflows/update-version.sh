#!/bin/bash

################################################################################
# Script: update-version.sh
# Description: Update a component's version across repo files
# Usage: update-version.sh [--dry-run] <component> <current_version> <latest_version>
# Components: pebble, acme-dns, operator, ubi9-python
#
# Paths are relative to the current directory (run from the repo root).
# Each substitution must change its file; a pattern that no longer matches
# is an error, so stale defaults fail loudly instead of being skipped.
#
# Options:
#   --dry-run   Print a unified diff of each change without modifying files
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
check_help "$@" && exit 0

dry_run=false
args=()
for arg in "$@"; do
	case "$arg" in
	--dry-run) dry_run=true ;;
	*) args+=("$arg") ;;
	esac
done

component="${args[0]:-}"
current="${args[1]:-}"
latest="${args[2]:-}"

if [ -z "$component" ] || [ -z "$current" ] || [ -z "$latest" ]; then
	echo "Usage: $0 [--dry-run] <component> <current_version> <latest_version>"
	exit 1
fi

setup_cleanup

# Apply sed expressions to a file, failing if nothing changed.
# In dry-run mode the edit is made on a temp copy and shown as a diff.
# Usage: substitute <file> <sed args...>
substitute() {
	local file="$1"
	shift
	local tmp
	tmp=$(mktemp)
	register_temp_file "$tmp"
	cp "$file" "$tmp"
	sed_inplace "$@" "$tmp"
	if cmp -s "$file" "$tmp"; then
		log_error "No change in $file — pattern for '$current' not found"
		exit 1
	fi
	if [ "$dry_run" = true ]; then
		diff -u --label "a/$file" --label "b/$file" "$file" "$tmp" || true
	else
		cat "$tmp" >"$file"
	fi
}

prefix=""
[ "$dry_run" = true ] && prefix="[dry-run] Would update"

case "$component" in
pebble)
	substitute scripts/install-pebble.sh \
		"s|PEBBLE_VERSION:-${current}|PEBBLE_VERSION:-${latest}|"
	substitute scripts/install-pebble-challtestsrv.sh \
		"s|PEBBLE_CHALLTESTSRV_VERSION:-v${current}|PEBBLE_CHALLTESTSRV_VERSION:-v${latest}|"
	echo "${prefix:-Updated} Pebble from $current to $latest in both install scripts"
	;;

acme-dns)
	substitute scripts/install-local-dns.sh \
		"s|ACMEDNS_VERSION:-${current}|ACMEDNS_VERSION:-${latest}|"
	echo "${prefix:-Updated} acme-dns from $current to $latest"
	;;

operator)
	substitute scripts/install-cert-manager-operator.sh \
		"s/CERT_MANAGER_VERSION:-${current}/CERT_MANAGER_VERSION:-${latest}/"
	substitute .env.example \
		"s/CERT_MANAGER_VERSION=${current}/CERT_MANAGER_VERSION=${latest}/"
	substitute CLAUDE.md "s/\`${current}\`/\`${latest}\`/"
	substitute scripts/workflows/check-olm-operator-bundle.sh \
		"s/CERT_MANAGER_VERSION:-${current}/CERT_MANAGER_VERSION:-${latest}/"
	substitute docs/installation.md "s/\`${current}\`/\`${latest}\`/"
	substitute docs/getting-started.md "s/\`${current}\`/\`${latest}\`/"
	substitute yaml/cert-manager-operator/README.md \
		-e "s/\`${current}\`/\`${latest}\`/" \
		-e "s/CERT_MANAGER_VERSION=\"${current}\"/CERT_MANAGER_VERSION=\"${latest}\"/" \
		-e "s/CHANNEL=\"stable-${current%.*}\"/CHANNEL=\"stable-${latest%.*}\"/"
	echo "${prefix:-Updated} default version from $current to $latest"
	;;

ubi9-python)
	substitute scripts/install-fake-dns.sh \
		"s|UBI9_PYTHON_VERSION:-${current}|UBI9_PYTHON_VERSION:-${latest}|"
	echo "${prefix:-Updated} UBI9 Python 3.9 from $current to $latest"
	;;

*)
	echo "Unknown component: $component"
	echo "Valid components: pebble, acme-dns, operator, ubi9-python"
	exit 1
	;;
esac
