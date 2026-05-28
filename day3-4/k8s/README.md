# Kubernetes — Day 3–4

Manifests for the **DevOps Portal** app (`../src/`). Run everything from this repo folder unless noted.

## Folder layout

```text
day3-4/
├── src/                      # Flask app + Dockerfile
└── k8s/
    ├── README.md             # ← you are here (concepts)
    ├── db-as-statefulset/    # Postgres — use this for DB
    ├── db-as-deployment/     # Postgres as Deployment (learning comparison only)
    └── main/                 # App Deployment variants, Secret, HPA, VPA
```

## Core concepts (short)

| Resource | What it is | In this project |
|----------|------------|-----------------|
| **Pod** | One or more containers running together | `postgres-0`, `devops-portal-xxxxx` |
| **Deployment** | Keeps stateless app pods running; random pod names; easy scale-out | Flask app in `main/` |
| **StatefulSet** | Like Deployment, but **stable pod names** and **per-pod storage** | Postgres in `db-as-statefulset/` |
| **Service** | Stable DNS name + load-balances to pods | `postgres:5432`, `devops-portal:80` |
| **Secret** | Stores sensitive config (passwords, DB URL) | `postgres-secret`, `devops-portal-secret` |
| **PVC** | Requests persistent disk for a pod | `postgres-data-postgres-0` (auto-created by StatefulSet) |
| **Probe** | K8s checks if a container is ready/alive | App: `GET /health`; DB: `pg_isready` |
| **HPA** | Scales pod count based on CPU/memory | `main/hpa.yaml` → app only |
| **PDB** | Limits how many pods can go down during maintenance | `deployment-full.yaml` |

## Deployment vs StatefulSet — why DB uses StatefulSet

**Deployment** — good for **stateless** apps (Flask):

- Pod names change on restart (`devops-portal-7f8b9-xyz`)
- Pods are interchangeable
- Scale up/down freely

**StatefulSet** — good for **databases** (Postgres):

- Stable pod name: `postgres-0`
- Each pod gets its **own** PVC (`volumeClaimTemplates`)
- Ordered start/stop (important if you ever run multiple replicas)

For a single Postgres instance, the app still connects via the Service name `postgres` — same as docker-compose.

## How traffic finds the DB

```text
devops-portal pod  →  Service "postgres"  →  pod postgres-0
                      (DNS: postgres:5432)
```

Inside the cluster, `DB_LINK` uses host `postgres` (see `main/secret.yaml`).

## Quick deploy

```bash
# From day3-4/src — build the image
docker build -t devops-portal:latest .
kind load docker-image devops-portal:latest   # or minikube image load ...

# From day3-4/k8s — database first (StatefulSet)
kubectl apply -f db-as-statefulset/
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s

# App
kubectl apply -f main/secret.yaml
kubectl apply -f main/deployment-full.yaml   # or deployment-simple.yaml to start

kubectl get pods,svc
kubectl port-forward svc/devops-portal 8080:80
curl http://localhost:8080/health
```

Details and variant comparison → [`main/README.md`](main/README.md).

## Exercises

`exercise1/` … `exercise6/` — smaller manifests for labs (HPA, monitoring, GitOps). See each folder’s instructions.
