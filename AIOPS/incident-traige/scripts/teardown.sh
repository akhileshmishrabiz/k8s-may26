#!/usr/bin/env bash
set -euo pipefail

CLUSTER="${CLUSTER_NAME:-incident-triage}"

echo "==> Deleting Kind cluster: ${CLUSTER}"
kind delete cluster --name "${CLUSTER}" 2>/dev/null || echo "    Cluster not found, nothing to delete"
echo "==> Done"
