# Incident Triage System

A hands-on AI Ops lab for learning incident detection, diagnosis, and remediation on Kubernetes.

We run three small Python microservices on a **Kind** cluster, backed by **Postgres (StatefulSet)**. A **Python dashboard** watches service health, injects failures on demand, and uses **OpenAI** (or rule-based fallback) to suggest root cause and remediation.

---

## What We Are Building

| Layer | Purpose |
|-------|---------|
| **3 microservices** | Simple Flask apps that talk to a shared Postgres DB |
| **Postgres StatefulSet** | Persistent database running inside Kind |
| **Triage dashboard** | FastAPI app — health view, chaos injection, AI analysis |
| **Chaos controls** | Buttons to break things safely and test triage |
| **AI triage** | Collects logs/events/health data and suggests fixes |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kind Cluster (namespace: incident-triage)            │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ catalog-svc  │  │  orders-svc  │  │ inventory-svc│  │
│  │   :5001      │  │   :5002      │  │   :5003      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                  │          │
│         └─────────────────┼──────────────────┘          │
│                           ▼                             │
│                  ┌─────────────────┐                    │
│                  │ Postgres (STS)  │                    │
│                  └─────────────────┘                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Triage Dashboard (:8080)                        │   │
│  │  • Health polling    • K8s logs/events          │   │
│  │  • Chaos injection   • AI / rule-based triage   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
                   OpenAI API (optional)
```

---

## Microservices

| Service | Port | Role |
|---------|------|------|
| `catalog-service` | 5001 | Products — list/create items |
| `orders-service` | 5002 | Orders — depends on catalog for validation |
| `inventory-service` | 5003 | Stock levels per product |

Each service exposes:

- `GET /health` — liveness
- `GET /ready` — checks DB (orders also checks catalog)
- Business API under `/api/...`

**Failure modes** (via `FAIL_MODE` env):

| Value | Behavior |
|-------|----------|
| `none` | Normal operation |
| `error` | API returns HTTP 500 |
| `latency` | 5 second delay on API calls |
| `crash` | Process exits (CrashLoopBackOff) |

---

## Dashboard Features

### 1. Health monitoring
- Polls `/health`, `/ready`, and smoke API calls every ~8 seconds
- Shows pod phase, restart count, and latency
- Tracks recent incidents

### 2. Failure injection (chaos)
Built-in scenarios you can trigger from the UI:

| Injection | What it breaks |
|-----------|----------------|
| DB unreachable | Wrong `DB_HOST` on all services |
| Bad credentials | Wrong password on catalog |
| HTTP 500 | `FAIL_MODE=error` on catalog |
| High latency | `FAIL_MODE=latency` on orders |
| Crash loop | `FAIL_MODE=crash` on inventory |
| Scale to zero | Replicas = 0 on catalog |

**Reset All** restores healthy env vars and scales services back to 1.

### 3. AI triage
On **Run AI Triage**, the dashboard collects:
- Health check results
- Deployment / pod status
- K8s events
- Recent pod logs

Then sends context to OpenAI (or uses built-in rules if no API key).

Output includes: summary, severity (P1/P2/P3), root cause, evidence, remediation steps.

### 4. Quick remediation (manual)
- **Restart** — rollout restart a deployment
- **Reset Env** — restore known-good env vars

---

## Project Layout

```
AIOPS/incident-traige/
├── README.md                    ← this file
├── .env.example                 ← OpenAI key, config
├── kind/
│   ├── kind-config.yaml         ← Kind cluster (port 8080 → dashboard)
│   └── manifests/               ← K8s YAML (namespace, DB, services, RBAC)
├── services/
│   ├── catalog-service/
│   ├── orders-service/
│   └── inventory-service/
└── dashboard/
    ├── app.py                   ← FastAPI main
    ├── health_monitor.py
    ├── k8s_collector.py
    ├── ai_triage.py
    ├── chaos.py
    └── templates/dashboard.html
```

---

## How to Run

### Prerequisites
- Docker, Kind, kubectl, Python 3.11+

### 1. Create Kind cluster
```bash
kind create cluster --name incident-triage --config kind/kind-config.yaml
```

### 2. Build and load images
```bash
docker build -t incident-triage/catalog-service:latest services/catalog-service
docker build -t incident-triage/orders-service:latest services/orders-service
docker build -t incident-triage/inventory-service:latest services/inventory-service
docker build -t incident-triage/dashboard:latest dashboard

kind load docker-image incident-triage/catalog-service:latest --name incident-triage
kind load docker-image incident-triage/orders-service:latest --name incident-triage
kind load docker-image incident-triage/inventory-service:latest --name incident-triage
kind load docker-image incident-triage/dashboard:latest --name incident-triage
```

### 3. Deploy to cluster
```bash
kubectl apply -f kind/manifests/
```

### 4. Open dashboard
```bash
# Via Kind NodePort mapping
open http://localhost:8080
```

### 5. (Optional) Enable OpenAI triage
```bash
cp .env.example .env
# Set OPENAI_API_KEY=sk-...
```

---

## Current Status

| Component | Status |
|-----------|--------|
| 3 Flask microservices | Done |
| Postgres StatefulSet | Done |
| K8s manifests + RBAC | Done |
| Health dashboard | Done |
| Chaos / failure injection | Done |
| AI triage (OpenAI + fallback) | Done |
| Manual remediation (restart, reset env) | Done |
| Setup / teardown scripts | Done |
| Automated AI remediation | Future |
| Metrics / alerting integration | Future |

---

## Future Building Path

### Phase 1 — Polish & operability *(next)*
- [x] `scripts/setup-kind.sh` and `scripts/teardown.sh` one-command deploy
- [x] Startup seed data (sample products + inventory)
- [x] Fix env consistency (`DB_HOST=postgres` in chaos reset)
- [x] Dashboard deployment manifest (`dashboard.yaml`)
- [ ] README run verification checklist

### Phase 2 — Richer observability
- [ ] Prometheus metrics on each microservice (`/metrics`)
- [ ] Grafana dashboard for golden signals (latency, errors, traffic)
- [ ] Loki or centralized log view in triage dashboard
- [ ] Trace IDs across orders → catalog calls

### Phase 3 — Smarter AI triage
- [ ] Structured remediation output (JSON actions, not just text)
- [ ] Incident history stored in DB (Postgres or SQLite)
- [ ] Compare AI diagnosis vs rule-based for demo scoring
- [ ] Support multiple LLM providers (OpenAI, local Ollama)

### Phase 4 — Automated remediation *(with guardrails)*
- [ ] Whitelist of safe auto-actions: restart, reset env, scale up
- [ ] **Approve / Reject** UI before any cluster mutation
- [ ] Auto-fix only for known chaos scenarios (e.g. after `db_unreachable`, restore `DB_HOST`)
- [ ] Rollback if health does not recover within N minutes
- [ ] Audit log of every AI-suggested and applied action

### Phase 5 — Production-style scenarios
- [ ] NetworkPolicy breakage (service can't reach DB)
- [ ] Resource limits (OOMKill demo)
- [ ] Cascading failure: catalog down → orders unhealthy
- [ ] Scheduled chaos (CronJob injects failure every hour)
- [ ] PagerDuty / Slack webhook on P1 incidents

### Phase 6 — Scale the demo
- [ ] Wire to existing repo ecommerce microservices (optional)
- [ ] Run on EKS instead of Kind
- [ ] GitOps: Argo CD detects drift and AI suggests sync
- [ ] Runbook library — AI picks from known runbooks before improvising

---

## Design Principles

1. **Safe by default** — chaos is reversible; AI analysis is read-only until Phase 4
2. **Self-contained** — everything lives under `AIOPS/incident-traige/`
3. **Learn by breaking** — inject failure → observe → triage → fix
4. **Progressive complexity** — start with health checks, add AI, then automation

---

## Related Work in This Repo

This demo is intentionally separate from the larger stacks under `microservices/` and `eks-microservices/` (RabbitMQ, Redis, multi-DB). Those can be integrated in Phase 6 if needed.
