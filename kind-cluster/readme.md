# cretae the kind cluster
kind create cluster --name cnpg-valut-eso --config kind-config.yaml


# install cnpg operator with helm

```bash
# 1. Add the repo and install the operator (Helm — cleanest)
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace

# 2. Verify the operator is running
kubectl get deployment -n cnpg-system cnpg-cloudnative-pg
kubectl get pods -n cnpg-system
```

# preload CNPG images (recommended — avoids 10+ min PodInitializing on slow networks)
```bash
./kind-load.sh cnpg-valut-eso
```

# create database
```bash
kubectl apply -f cluster.yaml
```
<!-- 
Here's the flow, what happens at each stage after kubectl apply:

API server stores the CR — your Cluster object is saved in etcd. Nothing is running yet; it's just a desired-state record.
Operator notices it — the CNPG controller is watching for Cluster resources. It picks up the new object and starts reconciling (comparing desired state vs reality).
Bootstrap the primary — the operator provisions the first data PVC + WAL PVC, then starts pod 1 and runs initdb inside it to create a fresh Postgres database from scratch. This pod becomes the primary.
Generate secrets — credentials for the superuser and the app user are auto-created and stored in Kubernetes secrets (pg-cluster-app, etc.).
Clone the replicas — for instance 2 and 3, the operator provisions their PVCs, then each new pod runs pg_basebackup to copy the primary's data and connects back as a streaming replica. They stay continuously synced via WAL streaming.
Create the services — three endpoints get wired up: -rw (always points to the primary, read-write), -ro (replicas, read-only), and -r (any instance). Apps connect to these, never to pods directly.
Continuous reconciliation — the operator keeps watching. If the primary dies, it promotes a healthy replica, repoints the -rw service, and rebuilds the failed instance. This self-healing loop is the whole reason you run an operator instead of raw StatefulSets.

The mental model for students: you declared what you want (3-node HA Postgres), and the operator figures out how — bootstrap one, clone the rest, wire the networking, then babysit it forever. -->

```bash
# 1. Watch the cluster come up (status goes: Setting up primary → Healthy)
kubectl get cluster pg-cluster -w

# 2. Watch the pods get created one by one (primary first, then replicas join)
kubectl get pods -l cnpg.io/cluster=pg-cluster -w

# 3. Confirm the PVCs were provisioned (should see 3 data + 3 WAL = 6)
kubectl get pvc -l cnpg.io/cluster=pg-cluster

# 4. See which pod is primary vs replica
kubectl get pods -l cnpg.io/cluster=pg-cluster -L cnpg.io/instanceRole

# 5. Check the services CNPG creates (-rw = primary, -ro/-r = replicas)
kubectl get svc -l cnpg.io/cluster=pg-cluster

# 6. Full health + topology summary (needs the cnpg kubectl plugin)
# kubectl cnpg status pg-cluster
```


# setting up vault

```bash

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault \
  -n vault --create-namespace \
  --set "server.dev.enabled=true"
```

# eso

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```


<!-- ```bash
# dev mode already has secret/ as kv-v2; write a test secret
vault kv put secret/myapp/config username=admin password=s3cret

# enable Kubernetes auth
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# policy: allow read on that path
vault policy write myapp - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# role: bind the policy to the ServiceAccount ESO will use
vault write auth/kubernetes/role/myapp \
  bound_service_account_names=eso-sa \
  bound_service_account_namespaces=default \
  policies=myapp \
  ttl=1h
exit
``` -->