#!/usr/bin/env bash

set -euo pipefail

OCP_VERSION="${OCP_VERSION:?OCP_VERSION must be set}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.0}"
OPERATOR_PACKAGE="${OPERATOR_PACKAGE:-openshift-cert-manager-operator}"
OPERATOR_CHANNEL="${OPERATOR_CHANNEL:-stable-v1}"
PYXIS_API="${PYXIS_API:-https://catalog.redhat.com/api/containers/v1/operators/bundles}"

if [[ ! "$OCP_VERSION" =~ ^4\.[0-9]+$ ]]; then
	echo "Invalid OCP_VERSION '$OCP_VERSION'; expected a version such as 4.20" >&2
	exit 2
fi

if [[ ! "$CERT_MANAGER_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Invalid CERT_MANAGER_VERSION '$CERT_MANAGER_VERSION'; expected a version such as v1.20.1" >&2
	exit 2
fi

for command in curl jq; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "Required command '$command' was not found" >&2
		exit 1
	fi
done

csv_name="cert-manager-operator.${CERT_MANAGER_VERSION}"
index_path="registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}"
filter="package==\"${OPERATOR_PACKAGE}\" and channel_name==\"${OPERATOR_CHANNEL}\" and ocp_version==\"${OCP_VERSION}\" and csv_name==\"${csv_name}\" and organization==\"redhat-operators\" and source_index_container_path==\"${index_path}\""

if ! response=$(curl --fail --silent --show-error --location \
	--retry 2 --retry-all-errors --retry-delay 2 --max-time 30 \
	--get "$PYXIS_API" \
	--data-urlencode "filter=$filter" \
	--data-urlencode 'include=data.csv_name,data.package,data.channel_name,data.ocp_version,data.in_index_img,data.organization,data.source_index_container_path' \
	--data-urlencode 'page_size=10'); then
	echo "Failed to query Red Hat OLM catalog availability from Pyxis" >&2
	exit 1
fi

available=$(jq -r \
	--arg csv_name "$csv_name" \
	--arg package "$OPERATOR_PACKAGE" \
	--arg channel "$OPERATOR_CHANNEL" \
	--arg ocp_version "$OCP_VERSION" \
	--arg organization redhat-operators \
	--arg index_path "$index_path" \
	'
	if (.data | type) != "array" then
		error("Pyxis response is missing the data array")
	else
		any(.data[];
			.csv_name == $csv_name and
			.package == $package and
			.channel_name == $channel and
			.ocp_version == $ocp_version and
			.in_index_img == true and
			.organization == $organization and
			.source_index_container_path == $index_path
		)
	end' <<<"$response")

if [[ "$available" == true ]]; then
	echo "OLM bundle image $csv_name is available in $index_path ($OPERATOR_CHANNEL); proceeding with CRC deployment."
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		echo 'available=true' >>"$GITHUB_OUTPUT"
	fi
	exit 0
fi

message="OLM bundle image $csv_name is not available yet in $index_path ($OPERATOR_CHANNEL); skipping CRC cluster deployment."
echo "$message"
echo "::notice title=OLM bundle not available::$message"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	echo 'available=false' >>"$GITHUB_OUTPUT"
fi
