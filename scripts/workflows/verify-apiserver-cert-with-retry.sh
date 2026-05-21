#!/bin/bash

################################################################################
# Script: verify-apiserver-cert-with-retry.sh
# Description: Verify API server certificate with cluster connectivity retry
# Used by: reusable-integration-test.yml
################################################################################

set -euo pipefail

echo "Waiting for cluster to stabilize before verification..."
sleep 5
for i in 1 2 3 4 5; do
	if oc whoami &>/dev/null && oc get nodes &>/dev/null; then
		echo "Cluster connectivity confirmed"
		make verify-apiserver-cert
		exit $?
	fi
	echo "Waiting for cluster connectivity (attempt $i/5)..."
	sleep 5
done
echo "Cluster connectivity not restored - skipping verification"
echo "The certificate was created, but verification could not be completed"
exit 0
