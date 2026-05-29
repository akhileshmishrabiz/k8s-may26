# Kubernetes Day 4 Assignment

**Bootcamp:** Real World Kubernetes on AWS  
**Date:** May 29, 2026  
**Topic:** Resource requests/limits, metrics-server, HPA, load testing, probes (liveness / readiness / startup)  
**Duration:** ~2 hours

---

## What you will learn

- Define **CPU and memory requests & limits** on containers
- Install **metrics-server** and read pod usage with `kubectl top`
- Configure **Horizontal Pod Autoscaler (HPA)** to scale web apps under load
- Simulate traffic with **Python**, **k6**, or **Apache Bench (ab)**
- Watch **scale-up** and **scale-down** behavior
- Understand **liveness**, **readiness**, and **startup** probes
- Know when **HPA** (horizontal) vs **VPA** (vertical) applies — and why databases use neither for replicas

**Repo folder:** `day3-4/`  
**Concepts cheat sheet:** [`k8s/README.md`](k8s/README.md)

---

## Prerequisites

Complete [assignment1.md](assignment1.md) first, or ensure you already have:

- A **multi-node Kind cluster** running (`kind-config.yaml`)
- **Postgres** deployed as a **StatefulSet** (`k8s/db-as-statefulset/`)
- **DevOps Portal** secret applied (`k8s/main/secret.yaml`)
- `kubectl`, Docker, and Python 3 installed

```bash
kubectl get nodes          # expect 4 nodes
kubectl get pod postgres-0 # expect Running
```

---

## Part 0 — Quick recap (5 mins)

Yesterday you built storage, Secrets, Deployments, StatefulSets, and Services. Today we add **production-style controls** on the same app.

Answer briefly:

1. Why is StatefulSet the right tool for Postgres, but Deployment is fine for the web app?
2. What happens to pod data when a Deployment pod is deleted and recreated?

---

## Part 1 — Requests and limits (20 mins)

Before autoscaling works sensibly, each container must declare **how much CPU/memory it needs** and **how much it is allowed to consume**.

| Field | Meaning |
|-------|---------|
| **requests** | Minimum guaranteed resources. The scheduler only places the pod on a node with this much free capacity. |
| **limits** | Maximum the container may use. Prevents one misbehaving app from starving the whole node. |

**Rule of thumb:** `limits` ≥ `requests`. Many teams start with limits ≈ 2× requests and tune from real metrics.

### Task 1.1 — Compare manifests

Open these files side by side:

- `k8s/main/deployment-simple.yaml` — no resources
- `k8s/main/deployment-resources.yaml` — requests + limits

```yaml
resources:
  requests:
    cpu: 100m        # 0.1 CPU (10% of one core)
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
```

**Questions:**

1. If a node has only 50m CPU free, will a pod requesting `cpu: 100m` schedule there?
2. If your app needs 200 Mi RAM to start but `requests.memory` is `128Mi`, what happens?
3. Why should `limits` not be set too high (e.g. 5 Gi on a 4 Gi node)?

### Task 1.2 — Deploy the resources variant

```bash
cd day3-4/k8s

kubectl apply -f db-as-statefulset/
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s

kubectl apply -f main/secret.yaml
kubectl apply -f main/deployment-resources.yaml
```

**Verify:**

```bash
kubectl get deploy devops-portal-resources
kubectl get pods -l app=devops-portal,variant=resources
kubectl describe pod -l app=devops-portal,variant=resources | grep -A6 "Limits\|Requests"
```

> **Important:** HPA only makes sense when **requests** are set. Without them, a pod can consume unbounded CPU/memory and the cluster never needs extra replicas.

---

## Part 2 — Install metrics-server (15 mins)

HPA scales based on **actual usage vs requests**. Something must measure usage — that component is **metrics-server**.

It is part of the Kubernetes ecosystem but **not pre-installed** on every cluster (including Kind).

### Task 2.1 — Apply metrics-server

From `day3-4/k8s/extra/`:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

On **Kind**, kubelet certificates are self-signed. Patch metrics-server (documented in [`k8s/extra/readme.md`](k8s/extra/readme.md)):

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Wait until ready:

```bash
kubectl rollout status deployment/metrics-server -n kube-system
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

### Task 2.2 — Confirm metrics work

```bash
kubectl top nodes
kubectl top pods -A
kubectl top pods -l app=devops-portal,variant=resources
```

**Before metrics-server:** `kubectl top` fails.  
**After:** you see CPU and memory columns for each pod.

**Questions:**

1. Why do both HPA and VPA depend on metrics-server?
2. Does metrics-server replace Prometheus? (hint: no — it is a lightweight API for basic autoscaling)

---

## Part 3 — Horizontal Pod Autoscaler (20 mins)

**HPA** adds or removes **copies** of a Deployment when average CPU or memory usage crosses a target.

- **Good for:** stateless web apps (our Flask portal)
- **Bad for:** databases, queues, anything with stable disk identity (use StatefulSet + vertical scaling instead)

Open `k8s/main/hpa.yaml`:

```yaml
scaleTargetRef:
  kind: Deployment
  name: devops-portal-resources   # must match your Deployment name
minReplicas: 1
maxReplicas: 6
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        averageUtilization: 50
```

When **both** CPU and memory are configured, HPA uses whichever metric demands **more** replicas.

### Task 3.1 — Apply HPA

Ensure the deployment has **1 replica** (edit `deployment-resources.yaml` if needed), then:

```bash
kubectl apply -f main/hpa.yaml
kubectl get hpa devops-portal-hpa
kubectl describe hpa devops-portal-hpa
```

**Verify baseline:**

```bash
kubectl get hpa devops-portal-hpa -o wide
# TARGETS might show memory already near 50% — that is normal for a small request value
```

**Questions:**

1. Why is `scaleTargetRef` a **Deployment**, not a Pod?
2. What is the difference between `minReplicas` and the Deployment's `replicas` field?
3. Read the `behavior.scaleDown` section — what does `stabilizationWindowSeconds: 5` do?

---

## Part 4 — Port-forward and load testing (35 mins)

To hit the app from your laptop, forward the Service to localhost.

### Task 4.1 — Port-forward

```bash
kubectl port-forward svc/devops-portal-resources 8081:8000
```

In another terminal, confirm the endpoint:

```bash
curl -I http://127.0.0.1:8081/
# expect HTTP 302 (redirect to /login) — that is fine for load testing
```

> Keep port-forward running for the whole load test. If it dies, k6/Python will show connection errors.

### Task 4.2 — Option A: Python load tester (simple)

```bash
cd day3-4/k8s/extra/load
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python load.py --url http://127.0.0.1:8081/ --users 100 --requests 2000 --delay 0.05
```

Tune until CPU/memory spike in `kubectl top pods`.

### Task 4.3 — Option B: k6 via Docker (recommended for heavy load)

No local install needed:

```bash
cd day3-4/k8s/extra/load

# smoke test (~15s)
docker run --rm -v "$(pwd):/scripts" grafana/k6 run \
  -e BASE_URL=http://host.docker.internal:8081 /scripts/load-smoke.js

# heavy spike — 500 virtual users for 3 minutes
docker run --rm -v "$(pwd):/scripts" grafana/k6 run \
  -e BASE_URL=http://host.docker.internal:8081 /scripts/load-heavy.js
```

On Linux (not Docker Desktop), use `http://127.0.0.1:8081` instead of `host.docker.internal`.

### Task 4.4 — Option C: Apache Bench in Docker (one-liner)

From [`k8s/extra/readme.md`](k8s/extra/readme.md):

```bash
docker run --rm jordi/ab -n 100000 -c 200 http://host.docker.internal:8081/
```

### Task 4.5 — Watch HPA scale **up**

While load runs, in a third terminal:

```bash
kubectl get hpa devops-portal-hpa -w
kubectl get pods -l app=devops-portal,variant=resources -w
kubectl top pods -l app=devops-portal,variant=resources
```

**Expected:** replicas increase from 1 toward `maxReplicas: 6` as CPU and/or memory exceed 50% of **requests**.

**Questions:**

1. Which metric triggered scale-up in your run — CPU, memory, or both?
2. Why does hitting `/` (login redirect) still generate CPU load?
3. Why might k6 report failures even when scaling works? (hint: 302 vs 200, timeouts under overload)

---

## Part 5 — Stop load and watch scale **down** (15 mins)

Stop the load generator (`Ctrl+C` on Python, or wait for k6 to finish).

```bash
kubectl get hpa devops-portal-hpa -w
kubectl get pods -l app=devops-portal,variant=resources
```

Scale-down is **slower and more conservative** than scale-up:

- HPA waits for metrics to stay **below** target for a stabilization window
- With CPU **and** memory targets, the **higher** recommendation wins — if memory stays at 54% while target is 50%, replicas stay at 5
- `behavior.scaleDown` removes at most **50% of pods per 60 seconds**

**Questions:**

1. After load stopped, did replicas drop immediately? If not, what did `kubectl describe hpa` show for memory vs CPU?
2. Why is aggressive scale-down risky in production? (hint: traffic spikes, cold pods, readiness)
3. How long did it take your cluster to return toward `minReplicas: 1`?

---

## Part 6 — Probes: liveness, readiness, startup (25 mins)

A pod can be `Running` while the **application inside** is broken. Probes automate health checks.

| Probe | When it runs | On failure |
|-------|----------------|------------|
| **startup** | Only while the container is starting | Blocks other probes; protects slow-start apps |
| **readiness** | After startup succeeds, on an interval | Pod removed from Service endpoints — **no traffic** |
| **liveness** | After startup succeeds, for the pod's lifetime | **Container restarted** (same pod) |

**Mental model:**

```text
New pod starts
    → startupProbe waits until app is up (or times out → restart pod)
    → readinessProbe passes → pod joins Service load balancing
    → livenessProbe keeps checking → failure restarts container only
```

### Task 6.1 — HTTP probes on the web app

Inspect `k8s/main/deployment-probes.yaml`:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: http
livenessProbe:
  httpGet:
    path: /health
    port: http
startupProbe:
  httpGet:
    path: /health
    port: http
  failureThreshold: 12   # 12 × periodSeconds ≈ grace time before kill
```

Deploy (optional lab — uses local image `devops-portal:latest`):

```bash
kubectl apply -f main/deployment-probes.yaml
kubectl describe pod -l app=devops-portal,variant=probes | grep -A3 "Liveness\|Readiness\|Startup"
```

### Task 6.2 — Exec probes on Postgres

Open `k8s/db-as-statefulset/statefulset.yaml` — Postgres uses **`pg_isready`** instead of HTTP:

```yaml
readinessProbe:
  exec:
    command: [pg_isready, -U, postgres, -d, mydb]
livenessProbe:
  exec:
    command: [pg_isready, -U, postgres, -d, mydb]
```

**Questions:**

1. A new pod passes liveness but fails readiness — can it receive traffic?
2. Why use **startupProbe** for an app that takes 60+ seconds to boot?
3. If startup and readiness hit the **same** `/health` endpoint, can you omit readiness? (hint: only if startup fully covers your use case)
4. Liveness failure restarts the **container**. Readiness failure does what to the **pod**?

---

## Part 7 — HPA vs VPA (conceptual, 10 mins)

| | **HPA** | **VPA** |
|---|---------|---------|
| Scales | Number of pod **replicas** | CPU/memory **per pod** |
| Direction | Horizontal (more copies) | Vertical (fatter pods) |
| Built into cluster? | Yes | No — install [VPA controller](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) |
| Best for | Web apps, workers | Apps that cannot scale out (some databases, legacy monoliths) |

See `k8s/main/vpa.yaml` for a sample VPA manifest ( **do not apply** unless the VPA controller is installed).

**Questions:**

1. Why did we **not** put HPA on the Postgres StatefulSet?
2. Can one pod span two nodes if VPA needs more CPU than a single node has free?
3. Changing requests/limits on a running pod used to require restart — why does that matter for databases?

---

## Part 8 — Reflection & interview prep (15 mins)

Answer in your own words:

1. **Requests vs limits** — what does the scheduler use? what does the kubelet enforce?
2. **metrics-server** — what breaks if it is missing?
3. **HPA** — walk through scale-up and scale-down using your lab numbers.
4. **Load testing** — why port-forward first, then hit `127.0.0.1`?
5. **Probes** — real-world failure: pod is green but users get 502. Which probe class is misconfigured?
6. **Production** — would you run k6 from inside the cluster instead of your laptop? Why?

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `kubectl top` says metrics not available | metrics-server not ready | Part 2; wait for rollout |
| HPA shows `<unknown>/50%` | metrics-server or missing requests | Patch Kind TLS flag; set resources on Deployment |
| HPA never scales up | Load too light or wrong Service | Increase users/VUs; confirm port-forward |
| HPA never scales down | Memory still above target | Wait; check `kubectl describe hpa`; memory often lags CPU |
| Load tool connection refused | Port-forward died | Restart `kubectl port-forward ... 8081:8000` |
| k6 high failure rate | App returns 302 not 200 | Expected for `/`; scaling still valid |

---

## Submission checklist

- [ ] metrics-server running; `kubectl top pods` works
- [ ] `devops-portal-resources` deployed with requests/limits
- [ ] HPA applied; screenshot of scale-up (replicas > 1 under load)
- [ ] Load test run (Python, k6, or ab) with port-forward on 8081
- [ ] Observed scale-down attempt after stopping load (note memory/CPU targets)
- [ ] Read `deployment-probes.yaml` and Postgres probes in `statefulset.yaml`
- [ ] Answers to all **Questions** sections

---

## Reference — folder map

```text
day3-4/
├── kind-config.yaml
├── assignment1.md                # May 28 — storage, StatefulSet, Services
├── assignment3.md                # This file — May 29
└── k8s/
    ├── README.md
    ├── db-as-statefulset/        # Postgres + pg_isready probes
    ├── main/
    │   ├── secret.yaml
    │   ├── deployment-simple.yaml
    │   ├── deployment-resources.yaml   # ← today's HPA target
    │   ├── deployment-probes.yaml      # ← liveness / readiness / startup
    │   ├── deployment-full.yaml
    │   ├── hpa.yaml
    │   └── vpa.yaml                    # reference only
    └── extra/
        ├── readme.md                   # metrics-server patch + ab one-liner
        └── load/
            ├── load.py                 # Python load tester
            ├── load.js                 # k6 ramped profile
            ├── load-heavy.js           # k6 500 VUs × 3 min
            ├── load-smoke.js           # k6 quick sanity check
            └── readme.md
```

---

## End-to-end command cheat sheet

Run from `day3-4/k8s` in order:

```bash
# 1. Database
kubectl apply -f db-as-statefulset/
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s

# 2. metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 3. App + HPA
kubectl apply -f main/secret.yaml
kubectl apply -f main/deployment-resources.yaml
kubectl apply -f main/hpa.yaml

# 4. Port-forward (terminal 1)
kubectl port-forward svc/devops-portal-resources 8081:8000

# 5. Load (terminal 2)
cd extra/load
docker run --rm -v "$(pwd):/scripts" grafana/k6 run \
  -e BASE_URL=http://host.docker.internal:8081 /scripts/load-heavy.js

# 6. Watch scaling (terminal 3)
kubectl get hpa devops-portal-hpa -w
```

---

## Coming next (preview)

- ConfigMaps and Ingress
- RDS as external database
- Running k6 **inside** the cluster for realistic microservice load tests
- Prometheus, Grafana, and probe failures in the wild
