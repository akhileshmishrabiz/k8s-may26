# Frontend Metrics & Grafana Setup

This document describes browser-side metrics for the DevOps Quiz SPA, how they reach Prometheus, and how to visualize them in Grafana.

## Architecture

SPAs cannot be scraped directly by Prometheus. The app uses a standard relay pattern:

```text
Browser (React)  →  POST /api/telemetry  →  backend Prometheus registry  →  GET /metrics  →  Prometheus  →  Grafana
```

The React app batches UI events and sends them to a minimal backend telemetry receiver. Those events increment `frontend_*` counters and histograms on the **same** `/metrics` endpoint the backend already exposes. No Pushgateway or extra infra is required.

### Distinction from backend metrics

| Source | Examples | Meaning |
|--------|----------|---------|
| **Backend** (`http_requests_total`, `quiz_starts_total`, …) | Server-side request handling, DB-backed quiz lifecycle | What the API actually processed |
| **Frontend** (`frontend_*`) | Page views, UI abandon/complete, client fetch failures, Web Vitals | What the user experienced in the browser |

Both appear on `/metrics`, but measure different things. For example, `quiz_starts_total` increments when the backend creates a session; `frontend_quiz_ui_events_total{event="quiz_started"}` increments when the quiz UI loads successfully.

---

## Frontend metrics reference

### `frontend_page_views_total` (Counter)

| Label | Description |
|-------|-------------|
| `route` | Normalized SPA path (e.g. `/`, `/quiz/docker`, `/leaderboard`) |

**Description:** Fired on every React Router navigation.

**Instrumented in:** `frontend/src/components/MetricsTracker.js`

---

### `frontend_quiz_ui_events_total` (Counter)

| Labels | Description |
|--------|-------------|
| `event` | `quiz_started`, `quiz_completed`, or `quiz_abandoned` |
| `topic` | Quiz topic slug |

**Description:** Quiz lifecycle from the UI perspective (start load, successful submit, navigate away before submit).

**Instrumented in:** `frontend/src/components/Quiz.js`

---

### `frontend_api_client_errors_total` (Counter)

| Labels | Description |
|--------|-------------|
| `endpoint` | API path; HTTP errors include status, e.g. `/api/quiz/docker/start [500]` |
| `error_type` | `http_error` (non-2xx response) or `network_error` (fetch threw) |

**Description:** Failed API calls observed in the browser. Does **not** duplicate backend `http_requests_total`.

**Instrumented in:** `frontend/src/services/metricsClient.js` via `instrumentedFetch`, used by `quizApi.js`, `api.js`, and `wikiService.js`.

---

### `frontend_web_vitals_seconds` (Histogram)

| Labels | Description |
|--------|-------------|
| `name` | `CLS`, `FID`, `FCP`, `LCP`, `TTFB`, or `INP` |
| `rating` | `good`, `needs-improvement`, or `poor` (from [web-vitals](https://github.com/GoogleChrome/web-vitals)) |

**Description:** Core Web Vitals from the browser. Time-based metrics (FID, FCP, LCP, TTFB, INP) are stored in **seconds**. CLS is a unitless layout-shift score (not seconds).

**Instrumented in:** `frontend/src/index.js` → `reportWebVitals`

---

### `frontend_quiz_duration_seconds` (Histogram)

| Labels | Description |
|--------|-------------|
| `topic` | Quiz topic slug |
| `outcome` | `passed`, `failed`, or `abandoned` |

**Description:** Time spent in the quiz UI before submit or abandonment.

**Instrumented in:** `frontend/src/components/Quiz.js`

---

## Telemetry API

**Endpoint:** `POST /api/telemetry`

**Body:**

```json
{
  "events": [
    { "type": "page_view", "route": "/leaderboard" },
    { "type": "quiz_ui_event", "event": "quiz_started", "topic": "docker" },
    { "type": "api_client_error", "endpoint": "/api/quiz/docker/start", "error_type": "http_error", "status": "500" },
    { "type": "web_vital", "name": "LCP", "value": 1.8, "rating": "good" },
    { "type": "quiz_duration", "topic": "docker", "outcome": "passed", "duration_seconds": 95 }
  ]
}
```

**Response:** `202 Accepted` with `{ "accepted": N, "received": M }`

The endpoint is excluded from backend `http_requests_total` to avoid noise from high-volume batched posts.

---

## Prometheus scrape configuration

### Static config (local / docker-compose)

Backend listens on port `8000`. Scrape `/metrics`:

```yaml
scrape_configs:
  - job_name: devops-quiz-backend
    static_configs:
      - targets: ['localhost:8000']
    metrics_path: /metrics
    scrape_interval: 15s
```

### Kubernetes ServiceMonitor (Prometheus Operator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: devops-quiz-backend
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: devops-quiz-backend
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Adjust `selector.matchLabels` and `port` to match your backend Service manifest.

---

## Example Grafana panel queries (PromQL)

### Page views by route (rate, 5m)

```promql
sum by (route) (rate(frontend_page_views_total[5m]))
```

### Quiz UI funnel

```promql
sum by (event) (increase(frontend_quiz_ui_events_total[1h]))
```

### Quiz abandon rate by topic

```promql
sum by (topic) (rate(frontend_quiz_ui_events_total{event="quiz_abandoned"}[5m]))
/
sum by (topic) (rate(frontend_quiz_ui_events_total{event="quiz_started"}[5m]))
```

### Client API errors by endpoint

```promql
sum by (endpoint, error_type) (rate(frontend_api_client_errors_total[5m]))
```

### LCP p75 (seconds)

```promql
histogram_quantile(
  0.75,
  sum by (le) (rate(frontend_web_vitals_seconds_bucket{name="LCP"}[5m]))
)
```

### LCP by rating (good vs poor)

```promql
sum by (rating) (rate(frontend_web_vitals_seconds_count{name="LCP"}[5m]))
```

### Median quiz duration by outcome

```promql
histogram_quantile(
  0.5,
  sum by (le, outcome) (rate(frontend_quiz_duration_seconds_bucket[1h]))
)
```

### Compare backend vs frontend quiz starts (sanity check)

```promql
# Backend (API processed)
sum(rate(quiz_starts_total[5m]))

# Frontend (UI loaded)
sum(rate(frontend_quiz_ui_events_total{event="quiz_started"}[5m]))
```

---

## Local verification

### 1. Send sample telemetry

With the backend running on port 8000:

```bash
curl -s -X POST http://localhost:8000/api/telemetry \
  -H 'Content-Type: application/json' \
  -d '{
    "events": [
      {"type": "page_view", "route": "/"},
      {"type": "quiz_ui_event", "event": "quiz_started", "topic": "docker"},
      {"type": "api_client_error", "endpoint": "/api/quiz/docker/start", "error_type": "http_error", "status": "500"},
      {"type": "web_vital", "name": "LCP", "value": 1.2, "rating": "good"},
      {"type": "quiz_duration", "topic": "docker", "outcome": "passed", "duration_seconds": 120}
    ]
  }'
```

Expected: `{"accepted":5,"received":5}`

### 2. Confirm metrics on `/metrics`

```bash
curl -s http://localhost:8000/metrics | grep '^frontend_'
```

You should see lines such as:

```text
frontend_page_views_total{route="/"} 1.0
frontend_quiz_ui_events_total{event="quiz_started",topic="docker"} 1.0
frontend_api_client_errors_total{endpoint="/api/quiz/docker/start [500]",error_type="http_error"} 1.0
frontend_web_vitals_seconds_bucket{...}
frontend_quiz_duration_seconds_bucket{...}
```

### 3. Docker Compose end-to-end

```bash
cd 3-tier-app/app
docker compose up --build -d
```

- Frontend: http://localhost:3000
- Backend metrics: http://localhost:8000/metrics
- Browse the app, start a quiz, then grep for `frontend_` on `/metrics`

### 4. Frontend build & tests

```bash
cd frontend
npm run build
CI=true npm test -- --watchAll=false
```

---

## Source files

| Area | File |
|------|------|
| Metrics client (batching, beacon flush) | `frontend/src/services/metricsClient.js` |
| Route page views | `frontend/src/components/MetricsTracker.js` |
| Quiz UI events & duration | `frontend/src/components/Quiz.js` |
| Web Vitals | `frontend/src/index.js` |
| Telemetry receiver | `backend/app/routes/telemetry_routes.py` |
| Prometheus definitions | `backend/app/frontend_metrics.py` |
