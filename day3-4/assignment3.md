# Kubernetes Day 3 Assignment

**Bootcamp:** Real World Kubernetes on AWS  
**Date:** May 28, 2026  
**Topic:** Multi-node clusters, persistent storage, Secrets, Deployment vs StatefulSet, two-tier apps  
**Duration:** ~2 hours

---

## What you will learn

- Create a **multi-node Kind cluster**
- Persist data with **StorageClass → PVC → Pod**
- Store credentials in **Secrets** (Opaque type)
- Run a **two-tier app** (Flask + Postgres) on Kubernetes
- Understand why **Deployment is wrong for databases** and **StatefulSet is the right tool**
- Use **ClusterIP**, **NodePort**, and **headless** Services

**Repo folder:** `day3-4/`  
**Concepts cheat sheet:** [`k8s/README.md`](k8s/README.md)

---

## Prerequisites

- Docker Desktop running
- [Kind](https://kind.sigs.k8s.io/) installed
- `kubectl` installed
- Basic familiarity with Day 1–2 (Pod, Deployment, Service)

---

## Part 0 — Set up a multi-node cluster (10 mins)

Yesterday we used a single-node cluster. Today we simulate a real setup: **1 control-plane + 3 workers**.

### Task 0.1 — Create the cluster

From `day3-4/`:

```bash
kind create cluster --name day3-kind --config kind-config.yaml
kubectl cluster-info --context kind-day3-kind
kubectl get nodes
```

**Verify:** You should see **4 nodes** — one `control-plane` and three `worker` nodes.

**Questions:**
1. Why does Kind run a `kindnet` pod on every node?
2. What is a CNI plugin, in one sentence?

---

## Part 1 — Persistent storage basics (20 mins)

Pod logs and container filesystems are **ephemeral**. When a pod dies, data is lost unless you attach storage.

### The chain

```text
Storage driver (plugin)  →  StorageClass  →  PVC  →  Pod volumeMount
```

You do **not** create a PersistentVolume by hand in most cases. The pod **claims** storage; the provisioner creates the disk.

### Task 1.1 — Inspect storage in your cluster

```bash
kubectl get storageclass
kubectl get sc -o yaml | grep -A2 volumeBindingMode
```

**Questions:**
1. What StorageClass does Kind provide by default?
2. What does `WaitForFirstConsumer` mean? Why is the PVC `Pending` before a pod exists?

### Task 1.2 — Create a PVC

```bash
cd day3-4/k8s/db-as-deployment
kubectl apply -f pvc.yaml
kubectl get pvc
kubectl get pv
```

**Verify:** PVC status is `Pending` (waiting for a pod to consume it).

**Questions:**
1. What is the difference between a **PersistentVolume (PV)** and a **PersistentVolumeClaim (PVC)**?
2. What does access mode `ReadWriteOnce` mean?

---

## Part 2 — Postgres as a Deployment (learning lab) (25 mins)

We run Postgres as a **Deployment** first — to see why it breaks at scale.

Manifests: `k8s/db-as-deployment/`

### Task 2.1 — Troubleshooting: deploy in the wrong order

**On purpose**, apply the Deployment **before** the Secret and PVC:

```bash
kubectl delete deployment postgres --ignore-not-found
kubectl delete pvc postgres-data --ignore-not-found

kubectl apply -f deployment.yaml
kubectl get pods
kubectl describe pod -l app=postgres
```

**Questions:**
1. Why is the pod stuck in `Pending`?
2. What event message mentions the PVC?

Now fix it step by step:

```bash
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f service.yaml
kubectl get pods,pvc
```

**Verify:**

```bash
kubectl wait --for=condition=available deployment/postgres --timeout=120s
kubectl exec -it deploy/postgres -- pg_isready -U postgres -d mydb
```

### Task 2.2 — Secrets (Opaque type)

Open `secret.yaml`. Yesterday we used a **dockerconfigjson** secret to pull private images. Today we use type **Opaque** for DB credentials.

**Questions:**
1. What is the difference between hardcoding `value: password` in a Deployment vs using `valueFrom.secretKeyRef`?
2. What happens if the Secret is in a **different namespace** than the pod?

### Task 2.3 — Scale the Deployment to 3 replicas (see the problem)

The repo ships with `replicas: 3` in `deployment.yaml`. If you changed it, set it back to 3 and re-apply:

```bash
kubectl apply -f deployment.yaml
kubectl get pods -l app=postgres
kubectl get pvc
```

**Questions:**
1. How many Postgres pods are running?
2. How many PVCs exist?
3. What happens when **multiple pods share one ReadWriteOnce volume** and all try to write to the same database files?
4. Why is this fine for **centralized logs** (each pod writes its own file) but **not** for a database?

> **Key takeaway:** Deployment gives random pod names and no per-pod storage binding. Fine for stateless apps and log volumes — **not** for databases.

---

## Part 3 — Deploy the DevOps Portal app (30 mins)

Two-tier app: **Flask app** (`src/`) + **Postgres** (already running).

### Task 3.1 — Build and load the app image

```bash
cd day3-4/src
docker build -t devops-portal:latest .
kind load docker-image devops-portal:latest --name day3-kind
```

> For EKS later: push to ECR/Docker Hub and update `image:` in the YAML.

### Task 3.2 — Understand DB_LINK

The app needs a Postgres connection string. Format:

```text
postgresql://<user>:<password>@<host>:<port>/<db_name>
```

| Part | In our cluster |
|------|----------------|
| user / password / db_name | From `postgres-secret` (`postgres` / `password` / `mydb`) |
| host | Kubernetes **Service name** → `postgres` |
| port | `5432` |

Full value (already in `k8s/main/secret.yaml`):

```text
postgresql://postgres:password@postgres:5432/mydb
```

**Questions:**
1. What is the difference between **DB host** and **DB name**?
2. Why do we use the Service name `postgres` instead of a pod IP?

### Task 3.3 — Deploy the app

```bash
cd day3-4/k8s/main
kubectl apply -f secret.yaml
kubectl apply -f deployment-simple.yaml
kubectl get pods,svc -l app=devops-portal
```

**Verify:**

```bash
kubectl logs -l app=devops-portal,variant=simple --tail=20
kubectl port-forward svc/devops-portal-simple 8080:8000
curl -s http://localhost:8080/health
```

Expected:

```json
{"status":"healthy","database":"connected"}
```

### Task 3.4 — Use the app

Open http://localhost:8080/login

| Username | Password |
|----------|----------|
| `livingdevops` | `LivingDevops1!` |
| `devopscaptain` | `ShipIt2026!` |

Try:
- Add a student on the portal
- Open a retro board and add a sticky note
- Kill the **app** pod — data should survive (Postgres still has it)
- Kill the **Postgres** pod — the Deployment recreates it; check if app data persists

**Questions:**
1. What Service type does `deployment-simple.yaml` use?
2. What is **NodePort**? Why is it rarely used in production?
3. Why do we use `kubectl port-forward` in local labs instead of NodePort?

---

## Part 4 — Postgres as a StatefulSet (30 mins)

Now run Postgres the **right way**.

### Task 4.1 — Tear down the Deployment-based DB

```bash
kubectl delete -f day3-4/k8s/db-as-deployment/ --ignore-not-found
kubectl delete -f day3-4/k8s/main/deployment-simple.yaml --ignore-not-found
```

> Do **not** run both `db-as-deployment` and `db-as-statefulset` in the same namespace — they share the Service name `postgres`.

### Task 4.2 — Deploy StatefulSet + headless Service

```bash
kubectl apply -f day3-4/k8s/db-as-statefulset/
kubectl get statefulset,pods,pvc
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s
```

**Verify:**

```bash
kubectl get svc postgres -o wide
kubectl exec -it postgres-0 -- pg_isready -U postgres -d mydb
```

**Questions:**
1. What is the pod name? Delete `postgres-0` and watch what name the replacement gets.
2. What PVC was auto-created? Notice the name ends in `-postgres-0`.
3. What is `clusterIP: None` on the Service? Why is it called a **headless** Service?
4. What three things does StatefulSet guarantee? (hint: **name**, **storage**, **order**)

### Task 4.3 — Re-deploy the app against StatefulSet Postgres

```bash
kubectl apply -f day3-4/k8s/main/secret.yaml
kubectl apply -f day3-4/k8s/main/deployment-simple.yaml
kubectl port-forward svc/devops-portal-simple 8080:8000
curl -s http://localhost:8080/health
```

Same `DB_LINK` works — host is still `postgres` (the Service).

### Task 4.4 — (Optional) Multi-replica StatefulSet demo

Inspect `k8s/db-as-statefulset/stateful2set.yaml` — a 2-replica demo with separate writer/reader Services.

**Do not apply this unless instructed.** In production, multi-replica Postgres needs an **operator** (backup, failover, connection pooling).

**Questions:**
1. Why does `postgres-1` get its **own** PVC?
2. What error might you see if a pod is rescheduled to a **different node** while its volume is still attached elsewhere? (hint: **Multi-Attach error**)

---

## Part 5 — Reflection & interview prep (15 mins)

Answer in your own words:

1. **Deployment vs StatefulSet** — when do you use each?
2. **StorageClass vs PVC** — who creates the actual disk?
3. **Secret types** — name two types and what each is for (`dockerconfigjson`, `Opaque`, `kubernetes.io/basic-auth`).
4. **Service types** — ClusterIP vs NodePort vs headless. Which does the app use? Which does the DB use?
5. **Troubleshooting** — a pod is `Pending`. Name **three** different causes you saw today and how you diagnosed each (`kubectl describe pod`).
6. **Production** — would you run Postgres inside Kubernetes or on RDS? What extra concerns exist for in-cluster DBs?

---

## Submission checklist

- [ ] Multi-node Kind cluster running (`kubectl get nodes` shows 4 nodes)
- [ ] Postgres ran as Deployment; you observed multi-replica + single PVC issue
- [ ] App deployed and `/health` returns `"database":"connected"`
- [ ] Postgres redeployed as StatefulSet; pod name is `postgres-0`
- [ ] Screenshot or terminal output of `kubectl get pods,pvc,svc`
- [ ] Answers to all **Questions** sections (copy into a doc or PR description)

---

## Reference — folder map

```text
day3-4/
├── kind-config.yaml              # Multi-node Kind cluster
├── assignment1.md                # This file
├── src/                          # DevOps Portal (Flask app)
│   ├── Dockerfile
│   └── docker-compose.yaml       # Local reference for env vars
└── k8s/
    ├── README.md                 # Short concepts guide
    ├── db-as-deployment/         # Part 2 — DB as Deployment (lab)
    ├── db-as-statefulset/        # Part 4 — DB as StatefulSet (recommended)
    └── main/                     # Part 3 — app manifests
        ├── secret.yaml
        ├── deployment-simple.yaml
        ├── deployment-probes.yaml
        ├── deployment-resources.yaml
        └── deployment-full.yaml
```

---

## Coming next (Day 4 preview)

- ConfigMaps
- Ingress
- RDS as external database (DB outside the cluster)
- Probes, HPA, and production-style deployments (`deployment-full.yaml`)
- DNS inside the cluster (`postgres.default.svc.cluster.local`)
