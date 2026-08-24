#!/bin/bash
################################################################################
# Script: validate-yaml.sh
# Description: Render yaml/ templates with dummy envsubst values and validate
#              Kubernetes objects with kubeconform (no cluster required).
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

cd "$REPO_ROOT"

if ! command -v kubeconform >/dev/null 2>&1; then
	log_error "kubeconform not found."
	log_hint "Install: go install github.com/yannh/kubeconform/cmd/kubeconform@v0.6.7"
	exit 1
fi
require_cmd envsubst

print_header "YAML schema validation (kubeconform)"

# Dummy-export every ${VAR} referenced in templates so envsubst does not emit
# empty names/namespaces. Do not load .env.
while IFS= read -r name; do
	[[ -z "$name" ]] && continue
	eval "export ${name}=\"\${${name}:-dummy}\""
done < <(grep -rhoE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' yaml --include='*.yaml' | sed 's/[${}]//g' | sort -u)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

count=0
while IFS= read -r -d '' yaml_file; do
	rel="${yaml_file#yaml/}"
	dest="$tmpdir/$rel"
	mkdir -p "$(dirname "$dest")"
	envsubst <"$yaml_file" >"$dest"
	count=$((count + 1))
done < <(find yaml -name '*.yaml' -type f -print0)

log_info "Rendered $count YAML file(s) into $tmpdir"
log_info "Running kubeconform -strict -ignore-missing-schemas..."

kubeconform -strict -summary -ignore-missing-schemas "$tmpdir"

log_success "kubeconform validation passed."
