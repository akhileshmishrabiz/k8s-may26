# E-commerce Microservices Helm Chart

Helm chart deploying the e-commerce microservices to EKS. Database persistence is provided by CloudNativePG `Cluster` resources; all secrets are sourced from Kubernetes Secrets that are materialised by External Secrets Operator from a centrally-deployed Vault.

The chart itself does **not** install Vault, ESO controller, or the CNPG operator — those are cluster-wide prerequisites managed in:

- `eks/k8s-services/vault-eso/` — Vault server + ESO controller (terraform, cluster-wide)
- `eks-microservice-implementation/infra/cnpg-operator/` — CNPG operator (terraform)
- `eks-microservice-implementation/infra/vault-secrets/` — terraform that generates random app creds, writes them to Vault, and (with `enable_eso_secrets=true`) creates the `ClusterSecretStore` + `ExternalSecret`s

See `../infra/README.md` for the full deploy order.

---

## What the chart deploys

| Resource | Purpose |
|----------|---------|
| `Namespace ecommerce` | All workloads land here |
| 4× `Cluster` (CNPG) | `products`, `users`, `orders`, `payments` PostgreSQL databases |
| `Deployment redis` | Cache backing for cart-service |
| `StatefulSet rabbitmq` | Message broker for order/notification |
| 6× microservice `Deployment` + `Service` | product, user, cart, order, payment, notification |
| `Deployment api-gateway` | nginx fronting the 6 services |
| `Deployment frontend` | Static UI |
| `Ingress` | ALB ingress (`shop.livingdevops.org`) on the shared ALB group `k8sbatch-shared-alb` |

> Source for the container images lives in `../apps/` — see `../README.md` for the build/push flow.

---

## Image registry

`values.yaml` sets `ecr.enabled: true` and lists image **short names** like `ecommerce-product-service`. The `ecommerce.image` helper composes the full ECR URI from `ecr.accountId` and `ecr.region`. To override with a fully-qualified URI, just set the service's `image` to one containing `/` and it will be used verbatim.

EKS worker nodes are expected to have `AmazonEC2ContainerRegistryReadOnly` on the node IAM role, so `imagePullSecrets` are not used.

---

## Secrets consumed

Pods reference six Kubernetes Secrets that must exist before install:

| Secret | Created by |
|--------|-----------|
| `db-credentials` | ESO `ExternalSecret` from `../infra/vault-secrets/eso.tf` |
| `db-app-credentials` | ESO `ExternalSecret` (CNPG bootstrap format: `username`/`password`) |
| `redis-credentials` | ESO |
| `rabbitmq-credentials` | ESO |
| `app-secrets` | ESO |
| `aws-credentials` | ESO |

CNPG `Cluster` bootstrap reads `db-app-credentials` to create the per-database app user.

---

## Install

```bash
# Prereqs applied (see ../infra/README.md):
#   1. CNPG operator       → terraform apply in ../infra/cnpg-operator/
#   2. Vault writes + ESO  → terraform apply in ../infra/vault-secrets/
#                            with -var enable_eso_secrets=true

# Render to verify
helm template ecommerce . | less

# Install
helm install ecommerce . -n ecommerce --create-namespace

# Upgrade
helm upgrade ecommerce . -n ecommerce
```

---

## Useful commands

```bash
# CNPG clusters
kubectl get clusters -n ecommerce
kubectl exec -it products-1 -n ecommerce -- psql -U ecommerce_user -d products

# Force ESO resync after Vault update
kubectl annotate externalsecret db-credentials -n ecommerce \
    force-sync=$(date +%s) --overwrite

# Restart services after a secret rotation
kubectl rollout restart deployment -n ecommerce
```

---

## Chart structure

```
helm-ecommerce/
├── Chart.yaml
├── values.yaml
├── README.md
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── cnpg-clusters.yaml
    ├── redis.yaml
    ├── rabbitmq.yaml
    ├── product-service.yaml
    ├── user-service.yaml
    ├── cart-service.yaml
    ├── order-service.yaml
    ├── payment-service.yaml
    ├── notification-service.yaml
    ├── api-gateway.yaml
    ├── frontend.yaml
    └── ingress.yaml
```
