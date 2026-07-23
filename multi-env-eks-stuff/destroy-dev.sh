#!/usr/bin/env bash
# Tear down dev + prod EKS stacks (reverse of deploy order). Requires valid AWS creds for ap-south-1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

aws sts get-caller-identity >/dev/null

destroy() {
  local dir="$1"
  local env="$2"
  echo "=== destroy: $dir (env=$env) ==="
  cd "$ROOT/$dir"
  terraform init -backend-config="vars/${env}.tfbackend" -reconfigure -input=false
  terraform destroy -var-file="vars/${env}.tfvars" -auto-approve
}

for env in prod dev; do
  destroy eks-microservices/infra/ms-ecom "$env"
done

for env in prod dev; do
  destroy EKS/k8s-services "$env"
done

for env in prod dev; do
  destroy EKS/core-cluster "$env"
done

echo "Dev and prod stacks destroyed."
