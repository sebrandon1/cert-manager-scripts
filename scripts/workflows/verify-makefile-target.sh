#!/bin/bash

set -euo pipefail

if ! grep -q "check-workload-partitioning:" Makefile; then
	echo "❌ check-workload-partitioning target not found in Makefile"
	exit 1
fi
echo "✅ Makefile target exists"
