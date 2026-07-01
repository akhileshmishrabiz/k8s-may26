#!/usr/bin/env bash
set -euo pipefail

# Pre-pull CNPG images and load them into a kind cluster.
# Avoids init/join pods sitting in PodInitializing for 10+ minutes on slow networks.

CLUSTER_NAME="cnpg-valut-eso"
OPERATOR_IMAGE="ghcr.io/cloudnative-pg/cloudnative-pg:1.29.1"
POSTGRES_IMAGE="ghcr.io/cloudnative-pg/postgresql:18.3-system-trixie"

usage() {
  cat <<EOF
Usage: $(basename "$0") [CLUSTER_NAME]

Pull CloudNativePG operator and PostgreSQL images, then load them into kind.

Arguments:
  CLUSTER_NAME  kind cluster name (default: cnpg-valut-eso)

Run this before: kubectl apply -f cluster.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      CLUSTER_NAME="$1"
      shift
      ;;
  esac
done

for cmd in kind docker; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: ${cmd} is not installed or not on PATH." >&2
    exit 1
  fi
done

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Error: kind cluster '${CLUSTER_NAME}' not found." >&2
  kind get clusters 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi

# kind load docker-image can fail with "ctr: content digest ... not found" when
# Docker's image store and kind node's containerd get out of sync. Import via
# docker save + ctr import on each node is reliable.
load_image_into_kind_nodes() {
  local image="$1"
  local cluster="$2"
  local node
  local node_count=0

  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    node_count=$((node_count + 1))
  done < <(kind get nodes --name "${cluster}")

  if [[ "${node_count}" -eq 0 ]]; then
    echo "Error: no nodes found for kind cluster '${cluster}'." >&2
    exit 1
  fi

  echo "Importing ${image} into ${node_count} node(s)..."
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    echo "  -> ${node}"
    docker save "${image}" | docker exec -i "${node}" ctr -n k8s.io images import -
  done < <(kind get nodes --name "${cluster}")
}

echo "Pulling CNPG images (this may take several minutes)..."
docker pull "${OPERATOR_IMAGE}"
docker pull "${POSTGRES_IMAGE}"

echo "Loading images into kind cluster '${CLUSTER_NAME}'..."
load_image_into_kind_nodes "${OPERATOR_IMAGE}" "${CLUSTER_NAME}"
load_image_into_kind_nodes "${POSTGRES_IMAGE}" "${CLUSTER_NAME}"

echo "Done. Images loaded:"
echo "  ${OPERATOR_IMAGE}"
echo "  ${POSTGRES_IMAGE}"
