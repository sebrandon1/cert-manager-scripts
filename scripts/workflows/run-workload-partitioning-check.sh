#!/bin/bash

set -euo pipefail

echo "=== Workload Partitioning Check ==="
make check-workload-partitioning
