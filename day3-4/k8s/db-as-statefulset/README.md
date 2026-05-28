# Postgres as a StatefulSet

Runs Postgres 15 as a **StatefulSet** with **volumeClaimTemplates** (per-pod PVC) and a **headless Service**.

**This is the default DB setup for Day 3–4.** Stable pod name, dedicated storage, ordered rollout.

Concepts → [`../README.md`](../README.md).

## Apply

From `day3-4/k8s`:

```bash
kubectl apply -f db-as-statefulset/
```

Or apply files individually:

```bash
kubectl apply -f secret.yaml
kubectl apply -f service.yaml
kubectl apply -f statefulset.yaml
```

## Verify

```bash
kubectl get statefulset postgres
kubectl get pods -l app=postgres
# Pod name is stable: postgres-0
kubectl exec -it postgres-0 -- pg_isready -U postgres -d mydb
```

## Point the app at this database

### Option A — Service name (single replica)

Works when `replicas: 1`. Same as Deployment pattern:

```text
DB_LINK=postgresql://postgres:password@postgres:5432/mydb
```

### Option B — Pod DNS (explicit, works with multiple replicas for read replicas later)

```text
DB_LINK=postgresql://postgres:password@postgres-0.postgres.<namespace>.svc.cluster.local:5432/mydb
```

Replace `<namespace>` with your namespace (e.g. `default` or `student-portal`).

| Scenario | Host in `DB_LINK` |
|----------|-------------------|
| Same namespace, 1 replica | `postgres` |
| Same namespace, specific pod | `postgres-0.postgres` |
| Cross-namespace | `postgres.<db-namespace>.svc.cluster.local` |
| Full pod FQDN | `postgres-0.postgres.<namespace>.svc.cluster.local` |

Example app Secret:

```yaml
stringData:
  DB_LINK: postgresql://postgres:password@postgres:5432/mydb
```

## Deployment vs StatefulSet

| | Deployment (`../db-as-deployment/`) | StatefulSet (this folder) |
|---|--------------------------------------|---------------------------|
| Pod name | Random suffix | Stable: `postgres-0` |
| Storage | Shared PVC | Dedicated PVC per pod |
| Service | ClusterIP | Headless (`clusterIP: None`) |
| Scale-out | Easy but risky for DB | Ordered, identity-aware |

Do **not** run both Postgres manifests in the same namespace — they use the same Service name `postgres`.
