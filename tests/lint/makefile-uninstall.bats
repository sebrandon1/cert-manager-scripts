#!/usr/bin/env bats
# Guards against the operator uninstall target drifting from the installer's
# coordinates. No cluster required.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	MAKEFILE="$REPO_ROOT/Makefile"
	INSTALLER="$REPO_ROOT/scripts/install-cert-manager-operator.sh"
}

recipe() {
	awk '/^uninstall-cert-manager-operator:/{found=1; next} found && /^[^[:space:]]/{exit} found' "$MAKEFILE"
}

installer_default() {
	sed -n "s/.*${1}:-\([^}]*\)}.*/\1/p" "$INSTALLER" | head -1
}

@test "uninstall target uses KUBE_CLI and operator variables" {
	run recipe
	[ "$status" -eq 0 ]
	[[ "$output" == *'$(KUBE_CLI) delete subscription $(OPERATOR_NAME)'* ]]
	[[ "$output" == *'-n $(OPERATOR_NAMESPACE)'* ]]
	[[ "$output" == *'operators.coreos.com/$(OPERATOR_PACKAGE).$(OPERATOR_NAMESPACE)'* ]]
	[[ "$output" != *'@oc '* ]]
}

@test "Makefile operator defaults match the installer" {
	local ns name
	ns=$(sed -n 's/^OPERATOR_NAMESPACE ?= //p' "$MAKEFILE")
	name=$(sed -n 's/^OPERATOR_NAME ?= //p' "$MAKEFILE")
	[ "$ns" = "$(installer_default OPERATOR_NAMESPACE)" ]
	[ "$name" = "$(installer_default OPERATOR_NAME)" ]
	[ "$name" = "$(sed -n 's/^OPERATOR_PACKAGE ?= //p' "$MAKEFILE")" ]
}
