# DevOps Portal — Kubernetes manifests

Four **Deployment variants** (pick one), plus shared **Secret**, **HPA**, and **VPA**.

Concepts overview → [`../README.md`](../README.md).

## Layout

```text
day3-4/k8s/main/
├── secret.yaml                 # DB_LINK, SECRET_KEY, admin passwords
├── deployment-simple.yaml      # 1. Minimal — no probes, no limits
├── deployment-resources.yaml   # 2. CPU/memory requests & limits
├── deployment-probes.yaml      # 3. Readiness, liveness, startup on /health
├── deployment-full.yaml        # 4. All of the above + PDB, anti-affinity, preStop
├── hpa.yaml                    # Horizontal Pod Autoscaler → devops-portal
├── vpa.yaml                    # Vertical Pod Autoscaler → devops-portal
└── README.md
```

## Prerequisites

1. **Build the app image** (from `day3-4/src`):

   ```bash
   cd day3-4/src
   docker build -t devops-portal:latest .
   ```

   For minikube/kind, load the image locally:

   ```bash
   kind load docker-image devops-portal:latest
   # or: minikube image load devops-portal:latest
   ```

   For EKS, push to ECR and update `image:` in the deployment YAMLs.

2. **Deploy Postgres as a StatefulSet** (recommended — from `day3-4/k8s`):

   ```bash
   kubectl apply -f db-as-statefulset/
   ```

   > `db-as-deployment/` exists for comparison only. Do not run both in the same namespace.

3. **Wait for Postgres**:

   ```bash
   kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s
   ```

## Point the app at the database

Edit `secret.yaml` → `DB_LINK` must match your Postgres Service and credentials.

| Postgres setup | `DB_LINK` value |
|----------------|-----------------|
| StatefulSet, same namespace (default) | `postgresql://postgres:password@postgres:5432/mydb` |
| Postgres in namespace `db` | `postgresql://postgres:password@postgres.db.svc.cluster.local:5432/mydb` |
| StatefulSet pod directly | `postgresql://postgres:password@postgres-0.postgres.svc.cluster.local:5432/mydb` |
| External RDS | `postgresql://user:pass@your-rds-host:5432/mydb` |

Apply the secret **before** the app Deployment:

```bash
kubectl apply -f secret.yaml
```

## Apply one app variant

Pick **one** deployment file (they use different resource names so you can compare side-by-side, but only run **one** in production):

```bash
# Learning / smoke test
kubectl apply -f deployment-simple.yaml

# With resource governance
kubectl apply -f deployment-resources.yaml

# With health probes (recommended minimum for prod)
kubectl apply -f deployment-probes.yaml

# Full stack — use with HPA/VPA below
kubectl apply -f deployment-full.yaml
```

## HPA & VPA (target `devops-portal` full Deployment)

```bash
# metrics-server required for HPA
kubectl apply -f hpa.yaml

# VPA controller must be installed in the cluster
kubectl apply -f vpa.yaml
```

Check scaling:

```bash
kubectl get hpa devops-portal-hpa
kubectl describe vpa devops-portal-vpa
kubectl top pods -l app=devops-portal
```

## Verify

```bash
kubectl get pods,svc -l app=devops-portal
kubectl port-forward svc/devops-portal 8080:80    # full variant (LoadBalancer → port 80)
kubectl port-forward svc/devops-portal-simple 8080:8000

curl http://localhost:8080/health
# {"status":"healthy","database":"connected"}
```

## Deployment variants compared

| Feature | simple | resources | probes | full |
|---------|:------:|:---------:|:------:|:----:|
| Replicas | 1 | 2 | 2 | 2 |
| CPU/memory limits | — | ✓ | — | ✓ |
| Readiness/liveness | — | — | ✓ | ✓ |
| Startup probe | — | — | ✓ | ✓ |
| Pod anti-affinity | — | — | — | ✓ |
| PodDisruptionBudget | — | — | — | ✓ |
| preStop grace | — | — | — | ✓ |
| Prometheus annotations | — | — | — | ✓ |
| Service type | NodePort | ClusterIP | ClusterIP | LoadBalancer |
| HPA/VPA target | — | — | — | ✓ (`devops-portal`) |

## End-to-end example

```bash
# Run from day3-4/k8s

# 1. Database (StatefulSet)
kubectl apply -f db-as-statefulset/
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s

# 2. App secrets + full deployment
kubectl apply -f main/secret.yaml
kubectl apply -f main/deployment-full.yaml

# 3. Autoscaling
kubectl apply -f main/hpa.yaml
kubectl apply -f main/vpa.yaml

# 4. Health check
kubectl port-forward svc/devops-portal 8080:80 &
curl -s http://localhost:8080/health | jq
```

Default admin login: `livingdevops` / `LivingDevops1!` (from `ADMIN_PASSWORD` in secret).
