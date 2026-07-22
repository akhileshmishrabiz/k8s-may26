#!/usr/bin/env bash
# Tear down dev EKS stack (reverse of deploy order). Requires valid AWS creds for ap-south-1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TFVARS="-var-file=env/dev.tfvars"

aws sts get-caller-identity >/dev/null

destroy() {
  local dir="$1"
  echo "=== destroy: $dir ==="
  cd "$ROOT/$dir"
  terraform init -input=false
  terraform destroy $TFVARS -auto-approve
}

destroy eks-microservices/infra/observability
destroy eks-microservices/infra/ms-ecom
destroy eks-microservices/infra/vault-secrets
destroy EKS/k8s-services
destroy EKS/core-cluster

echo "Dev stack destroyed."
