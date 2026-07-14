# E-commerce Platform Infra

Terraform modules the `helm-ecommerce/` chart depends on. Apply them in order before `helm install`.

```
infra/
├── cnpg-operator/    # CloudNativePG operator (cluster-wide CRDs + controller)
├── vault-secrets/    # Generates random app creds, writes them to Vault, optionally wires ESO
└── observability/    # PodMonitors + PrometheusRules + Grafana dashboards for the ecommerce apps
```

Vault server and the ESO controller themselves are not here — those are deployed once per cluster from `eks/k8s-services/vault-eso/`. Same goes for Prometheus/Grafana/Loki — they live in `eks/k8s-services/logging-monitoring/`; `observability/` only adds app-level scrape configs, alerts, and dashboards on top.

---

## 1. CNPG operator

```bash
cd infra/cnpg-operator
terraform init
terraform apply
```

Installs the CloudNativePG operator into `cnpg-system`. After this, the chart's `Cluster` resources in `templates/cnpg-clusters.yaml` can be created.

## 2. Vault secrets

Generates strong random passwords for the database, Redis, RabbitMQ, and JWT signing key with the `random` provider, then writes them to Vault's KV v2 `secret/` mount using the `vault` provider. Razorpay and AWS credentials default to placeholders — override via tfvars or `-var` when wiring real values.

Because Vault is in-cluster, port-forward it first:

```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
```

Then apply (Stage 1: vault writes only):

```bash
cd infra/vault-secrets
terraform init
terraform apply \
  -var vault_addr=http://localhost:8200 \
  -var vault_token=root
```

`terraform output -json vault_paths` shows the KV paths written. Sensitive outputs:

```bash
terraform output -raw db_password
terraform output -raw jwt_secret
```

### Stage 2: enable the ESO ClusterSecretStore + ExternalSecrets

Set `enable_eso_secrets=true` to also create:

- A `vault-token` Secret in the `external-secrets` namespace (used by ESO to auth to Vault)
- A `ClusterSecretStore` named `vault-backend` pointing at the in-cluster Vault
- Six `ExternalSecret` resources in the `ecommerce` namespace

Prerequisites for Stage 2:

- ESO CRDs must be installed (they are, via `eks/k8s-services/vault-eso/`)
- The `ecommerce` namespace must exist (helm chart creates it via `--create-namespace`, or run `kubectl create namespace ecommerce` first)

```bash
terraform apply \
  -var vault_addr=http://localhost:8200 \
  -var vault_token=root \
  -var enable_eso_secrets=true
```

---

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `vault_addr` | `http://localhost:8200` | Vault URL terraform writes to (use port-forward) |
| `vault_token` | `root` | Vault auth token (dev-mode root) |
| `vault_in_cluster_addr` | `http://vault.vault.svc.cluster.local:8200` | URL ESO uses from inside the cluster |
| `enable_eso_secrets` | `false` | Toggle creation of ClusterSecretStore + ExternalSecrets |
| `cluster_name` | `eks-cluster` | EKS cluster for the kubernetes provider |
| `db_user` / `rabbitmq_user` | `ecommerce_user` / `rabbitmq` | Static usernames; passwords are random |
| `razorpay_*` / `aws_*` | placeholders | Override when wiring real external creds |

---

## What the chart consumes

After Stage 2, ESO produces these K8s secrets in the `ecommerce` namespace:

| Secret | Keys | Vault path |
|--------|------|------------|
| `db-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `username`, `password` | `secret/ecommerce/database` — apps + CNPG bootstrap |
| `redis-credentials` | `REDIS_PASSWORD` | `secret/ecommerce/redis` |
| `rabbitmq-credentials` | `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS` | `secret/ecommerce/rabbitmq` |
| `app-secrets` | `JWT_SECRET`, `RAZORPAY_*` | `secret/ecommerce/app` + `/razorpay` |
| `aws-credentials` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `secret/ecommerce/aws` |

---

## Rotating a password

```bash
cd infra/vault-secrets
terraform taint random_password.db
terraform apply -var enable_eso_secrets=true   # new random written to Vault

# ESO picks the new value on the next refresh (interval: 1h). Force immediate:
kubectl annotate externalsecret db-credentials -n ecommerce \
    force-sync=$(date +%s) --overwrite

# Roll dependent pods
kubectl rollout restart deployment -n ecommerce
```

> Rotating a DB password also requires updating the user in PostgreSQL itself — CNPG only sets the password at `initdb` bootstrap time. Use a follow-up `ALTER USER` for live rotations.
