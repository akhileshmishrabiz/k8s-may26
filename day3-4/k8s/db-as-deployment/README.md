# Postgres as a Deployment (comparison only)

Runs Postgres 15 as a single-replica **Deployment** with a **PersistentVolumeClaim**.

> **Use `../db-as-statefulset/` instead** for Day 3–4. Deployments can reschedule pods to different nodes — fine for learning, not ideal for databases.

## Apply

```bash
kubectl apply -f secret.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Or:

```bash
kubectl apply -f .
```

## Verify

```bash
kubectl get pods -l app=postgres
kubectl get svc postgres
kubectl exec -it deploy/postgres -- pg_isready -U postgres -d mydb
```

## Point the app at this database

The Service name is **`postgres`** on port **5432** (same namespace).

```text
DB_LINK=postgresql://postgres:password@postgres:5432/mydb
```

| Scenario | `DB_LINK` host |
|----------|----------------|
| App in **same namespace** | `postgres` |
| App in **another namespace** (`app-ns`) | `postgres.<db-namespace>.svc.cluster.local` |
| Full DNS | `postgres.<namespace>.svc.cluster.local` |

Example app Secret (`k8s/main/secret.yaml`):

```yaml
stringData:
  DB_LINK: postgresql://postgres:password@postgres:5432/mydb
```

Apply the app secret **after** Postgres is ready:

```bash
kubectl wait --for=condition=available deployment/postgres --timeout=120s
kubectl apply -f ../main/secret.yaml
kubectl apply -f ../main/deployment-probes.yaml   # or any app manifest
```

Credentials must match `secret.yaml` in this folder (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).




# postgres link will loo like
postgresql://<username>:<password>@<db_host>/<db_name>