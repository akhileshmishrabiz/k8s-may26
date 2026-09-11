import time
from contextlib import contextmanager

from prometheus_client import Counter, Histogram

# HTTP metrics are added by prometheus-fastapi-instrumentator

LLM_TOKENS = Counter(
    "rag_llm_tokens_total",
    "OpenAI tokens consumed",
    ["operation", "token_type"],
)

RAG_OPS = Counter(
    "rag_operations_total",
    "RAG operations completed",
    ["operation", "status"],
)

RAG_STAGE_SECONDS = Histogram(
    "rag_stage_duration_seconds",
    "Time spent in a RAG pipeline stage",
    ["stage"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0),
)


def record_tokens(operation: str, prompt: int = 0, completion: int = 0, total: int | None = None) -> None:
    if prompt:
        LLM_TOKENS.labels(operation=operation, token_type="prompt").inc(prompt)
    if completion:
        LLM_TOKENS.labels(operation=operation, token_type="completion").inc(completion)
    t = total if total is not None else prompt + completion
    if t:
        LLM_TOKENS.labels(operation=operation, token_type="total").inc(t)


def record_operation(operation: str, status: str = "ok") -> None:
    RAG_OPS.labels(operation=operation, status=status).inc()


@contextmanager
def observe_stage(stage: str):
    start = time.perf_counter()
    try:
        yield
    finally:
        RAG_STAGE_SECONDS.labels(stage=stage).observe(time.perf_counter() - start)
