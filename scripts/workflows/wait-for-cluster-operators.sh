#!/bin/bash

################################################################################
# Script: wait-for-cluster-operators.sh
# Description: Poll cluster operators until all are healthy (5 min timeout)
# Used by: reusable-integration-test.yml
################################################################################

set -euo pipefail

echo "Waiting for cluster operators to stabilize (up to 5 minutes)..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
	degraded=$(oc get clusteroperators --no-headers 2>/dev/null | awk '($3!="True" || $4=="True" || $5=="True")' | wc -l | xargs)
	if [ "$degraded" -eq 0 ]; then
		echo "All cluster operators are healthy!"
		oc get clusteroperators
		break
	fi
	if [ $((elapsed % 30)) -eq 0 ]; then
		echo "Still waiting... ($elapsed seconds, $degraded operators not ready)"
	fi
	sleep 10
	elapsed=$((elapsed + 10))
done
echo "Cluster operator status:"
oc get clusteroperators || true
