#!/usr/bin/env bash
set -euo pipefail

# Build custom app images and load them into a kind cluster.
# Postgres (postgres:15) is pulled by Kubernetes from Docker Hub — not handled here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_CONTEXT="${SCRIPT_DIR}/app/backend"
FRONTEND_CONTEXT="${SCRIPT_DIR}/app/frontend"

BACKEND_IMAGE="devops-backend:local"
FRONTEND_IMAGE="devops-frontend:local"

CLUSTER_NAME="kind"
NO_BUILD=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [CLUSTER_NAME]

Build devops-app backend and frontend images and load them into kind.

Options:
  --no-build    Skip docker build; only load existing local images
  -h, --help    Show this help

Arguments:
  CLUSTER_NAME  kind cluster name (default: kind)

Examples:
  $(basename "$0")
  $(basename "$0") my-kind-cluster
  $(basename "$0") --no-build
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      NO_BUILD=true
      shift
      ;;
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

if ! command -v kind >/dev/null 2>&1; then
  echo "Error: kind is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not on PATH." >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Error: kind cluster '${CLUSTER_NAME}' not found." >&2
  echo "Create it first, e.g.: kind create cluster --name ${CLUSTER_NAME}" >&2
  echo "Existing clusters:" >&2
  kind get clusters 2>/dev/null | sed 's/^/  /' >&2 || true
  exit 1
fi

echo "Using kind cluster: ${CLUSTER_NAME}"

if [[ "${NO_BUILD}" == false ]]; then
  echo "Building ${BACKEND_IMAGE} from ${BACKEND_CONTEXT}"
  docker build -t "${BACKEND_IMAGE}" "${BACKEND_CONTEXT}"

  echo "Building ${FRONTEND_IMAGE} from ${FRONTEND_CONTEXT}"
  docker build -t "${FRONTEND_IMAGE}" "${FRONTEND_CONTEXT}"
else
  echo "Skipping build (--no-build)"
  for img in "${BACKEND_IMAGE}" "${FRONTEND_IMAGE}"; do
    if ! docker image inspect "${img}" >/dev/null 2>&1; then
      echo "Error: local image '${img}' not found. Run without --no-build first." >&2
      exit 1
    fi
  done
fi

echo "Loading ${BACKEND_IMAGE} into kind cluster '${CLUSTER_NAME}'"
kind load docker-image "${BACKEND_IMAGE}" --name "${CLUSTER_NAME}"

echo "Loading ${FRONTEND_IMAGE} into kind cluster '${CLUSTER_NAME}'"
kind load docker-image "${FRONTEND_IMAGE}" --name "${CLUSTER_NAME}"

echo "Done. Images loaded:"
echo "  ${BACKEND_IMAGE}"
echo "  ${FRONTEND_IMAGE}"
echo ""
echo "Deploy with:"
echo "  kubectl apply -f ${SCRIPT_DIR}/k8s/"
