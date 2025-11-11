#!/bin/bash

set -euo pipefail

if [ ! -x scripts/troubleshooting/check-workload-partitioning.sh ]; then
	echo "❌ Workload partitioning check script is not executable"
	exit 1
fi
echo "✅ Workload partitioning check script is executable"
