#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER_NAME:-incident-triage}"

echo "==> Creating Kind cluster: ${CLUSTER}"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo "    Cluster already exists, skipping create"
else
  kind create cluster --name "${CLUSTER}" --config "${ROOT}/kind/kind-config.yaml"
fi

echo "==> Building Docker images"
for svc in catalog-service orders-service inventory-service; do
  docker build -t "incident-triage/${svc}:latest" "${ROOT}/services/${svc}"
done
docker build -t incident-triage/dashboard:latest "${ROOT}/dashboard"

echo "==> Loading images into Kind"
for img in catalog-service orders-service inventory-service dashboard; do
  kind load docker-image "incident-triage/${img}:latest" --name "${CLUSTER}"
done

echo "==> Deploying manifests"
kubectl apply -f "${ROOT}/kind/manifests/namespace.yaml"
kubectl apply -f "${ROOT}/kind/manifests/secrets.yaml"
kubectl apply -f "${ROOT}/kind/manifests/postgres-statefulset.yaml"

echo "    Waiting for Postgres..."
kubectl wait --for=condition=ready pod -l app=postgres -n incident-triage --timeout=120s

kubectl apply -f "${ROOT}/kind/manifests/catalog-service.yaml"
kubectl apply -f "${ROOT}/kind/manifests/orders-service.yaml"
kubectl apply -f "${ROOT}/kind/manifests/inventory-service.yaml"
kubectl apply -f "${ROOT}/kind/manifests/dashboard-rbac.yaml"
kubectl apply -f "${ROOT}/kind/manifests/dashboard.yaml"

echo "    Waiting for all pods..."
kubectl wait --for=condition=ready pod -l app=catalog-service -n incident-triage --timeout=120s
kubectl wait --for=condition=ready pod -l app=orders-service -n incident-triage --timeout=120s
kubectl wait --for=condition=ready pod -l app=inventory-service -n incident-triage --timeout=120s
kubectl wait --for=condition=ready pod -l app=triage-dashboard -n incident-triage --timeout=120s

echo ""
echo "==> Incident Triage is live!"
echo "    Dashboard: http://localhost:8080"
echo "    Pods:"
kubectl get pods -n incident-triage
echo ""
echo "    Optional: set OpenAI key"
echo "    kubectl create secret generic openai-api-key -n incident-triage \\"
echo "      --from-literal=OPENAI_API_KEY=sk-... --dry-run=client -o yaml | kubectl apply -f -"
echo "    kubectl rollout restart deployment/triage-dashboard -n incident-triage"
