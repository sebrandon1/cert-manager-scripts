#!/bin/bash

set -euo pipefail

if [ ! -f scripts/troubleshooting/check-workload-partitioning.sh ]; then
	echo "❌ Workload partitioning check script not found"
	exit 1
fi
echo "✅ Workload partitioning check script exists"
