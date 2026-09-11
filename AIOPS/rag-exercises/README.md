# RAG lab exercises (3 parts)

Progressive hands-on labs: **basic RAG → RAG + metrics → local Gemma on Ollama**. Each part is a separate Docker Compose project. Run **one stack at a time** (Exercises 1 and 2 share ports `8001` / `8080`; Exercise 3 uses `8002` / `8081`).

| Part | Folder | LLM | Observability |
|------|--------|-----|----------------|
| 1 | [`simple-rag`](../simple-rag/) | OpenAI (cloud) | None |
| 2 | [`simle-rag-with-observibility`](../simle-rag-with-observibility/) | OpenAI (cloud) | Prometheus + Grafana |
| 3 | [`rag-with-local-llm`](../rag-with-local-llm/) | **Gemma 2** (`gemma2:2b`) via Ollama | None (compare latency yourself) |

**Prerequisites:** Docker Desktop (or Docker Engine + Compose), ~8 GB free disk for Part 3 model pulls. Parts 1–2 need an [OpenAI API key](https://platform.openai.com/api-keys).

---

## Before each part

```bash
# Stop whatever RAG stack is running (run from that project directory)
docker compose down
```

---

## Exercise 1 — Play with RAG

**Goal:** Ingest text, retrieve chunks, and see grounded answers with citations.

```bash
cd AIOPS/simple-rag
cp .env.example .env   # set OPENAI_API_KEY=sk-...
docker compose up --build
```

| What | URL |
|------|-----|
| Web UI | http://localhost:8080 |
| Swagger | http://localhost:8080/docs |
| Health | http://localhost:8080/health |

### Tasks

1. **Seed check** — Open `/health`. Confirm `documents` / `chunks` > 0 (sample `kubernetes-faq.txt` is ingested on startup when the API key is set).
2. **Chat** — `POST /chat` with: *What is a Kubernetes Pod?* Note `reply` and `sources` (file, chunk, score).
3. **Upload** — Upload a small `.txt` you write (3–5 sentences). Ask a question only answerable from that file.
4. **Failure mode** — Ask something **not** in your docs. See how the prompt instructs the model to say it does not know.
5. **Peek at the pipeline** — In [`simple-rag/rag.py`](../simple-rag/rag.py), find: chunking → embed → Chroma query → chat with context.

### Reflection

- What happens if you increase `top_k` in the request body?
- Where would bad chunk size hurt retrieval quality?

---

## Exercise 2 — RAG with observability

**Goal:** Same RAG flow as Part 1, plus **token usage**, **stage latency**, and **HTTP SLOs** in Grafana.

```bash
cd AIOPS/simle-rag-with-observibility
cp .env.example .env   # OPENAI_API_KEY required
docker compose up --build
```

| What | URL | Login |
|------|-----|--------|
| API | http://localhost:8080 | — |
| Grafana | http://localhost:3000 | `admin` / `admin` |
| Prometheus | http://localhost:9090 | — |
| Raw metrics | http://localhost:8080/metrics | — |

### Tasks

1. **Generate load** — Send 10–20 `POST /chat` requests (UI or Swagger). Vary message length.
2. **Grafana** — Open dashboard **Simple RAG Observability**. Watch:
   - HTTP request rate and **p95 latency**
   - **LLM tokens / min** (`query_embed`, `chat`, `ingest_embed`)
   - **RAG stage latency** (embed, retrieve, chat)
3. **Prometheus** — In http://localhost:9090/graph, run:
   ```promql
   sum(rate(rag_llm_tokens_total{operation="chat",token_type="total"}[5m]))
   ```
   ```promql
   histogram_quantile(0.95, sum(rate(rag_stage_duration_seconds_bucket{stage="chat"}[5m])) by (le))
   ```
4. **Ingest vs query** — Upload a new file, then chat again. Which metrics move: `rag_operations_total`, token counters, or stage histograms?
5. **Code trace** — Open [`metrics.py`](../simle-rag-with-observibility/metrics.py) and [`rag.py`](../simle-rag-with-observibility/rag.py). Match `observe_stage(...)` and `record_tokens(...)` to Grafana panels.

### Reflection

- Which stage dominates p95 on your machine: embed, retrieve, or chat?
- What alert would you write in Prometheus for “chat p95 > 5s for 5m”?

---

## Exercise 3 — Self-hosted LLM (Gemma on Ollama)

**Goal:** Run RAG **without OpenAI** — embeddings and chat through **Ollama** with **Gemma 2 2B** and `nomic-embed-text`.

```bash
cd AIOPS/rag-with-local-llm
docker compose up --build
```

First start pulls models (`gemma2:2b`, `nomic-embed-text`) via the `ollama-init` service. This can take **several minutes** and needs network bandwidth.

| What | URL |
|------|-----|
| API | http://localhost:8081 |
| Swagger | http://localhost:8081/docs |
| Ollama (host) | http://localhost:11435 |

No `.env` or API key required for this stack.

### Tasks

1. **Wait for models** — Follow logs until `ollama-init` exits successfully and the API is up:
   ```bash
   docker compose logs -f ollama-init
   ```
2. **Verify models** — From the host:
   ```bash
   curl http://localhost:11435/api/tags
   ```
   Expect `gemma2:2b` and `nomic-embed-text`.
3. **Chat** — Ask the same Pod question as Exercise 1. Compare answer quality and **wall-clock time** vs OpenAI.
4. **Config** — In [`docker-compose.yml`](../rag-with-local-llm/docker-compose.yml), note `OLLAMA_CHAT_MODEL=gemma2:2b`. Change to a model you have pulled (e.g. `llama3.2:3b`) only after `ollama pull` inside the Ollama container.
5. **Resource check** — While chatting, watch CPU/RAM. Would this model size fit your laptop for demos? For production?

### Optional stretch

- Run Exercise 2’s Prometheus metrics on the local-LLM app (copy `metrics.py` + instrumentator pattern from `simle-rag-with-observibility`).
- Compare token metrics: Ollama may not expose the same usage fields as OpenAI — what would you instrument instead?

### Reflection

- Trade-offs: cloud OpenAI vs local Gemma (cost, privacy, latency, quality).
- Why separate embedding and chat models?

---

## Suggested order (one afternoon)

```text
Exercise 1 (45 min) → Exercise 2 (45 min) → Exercise 3 (60+ min, includes model download)
```

## Teardown

```bash
docker compose down
# Optional: remove volumes and downloaded models
docker compose down -v
```

For Ollama model cache only: `docker volume rm rag-with-local-llm_ollama_data` (volume name may differ; check `docker volume ls`).
