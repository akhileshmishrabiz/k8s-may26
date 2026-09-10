from prometheus_client import Counter, Histogram

# HTTP-level (also covered by instrumentator; these are RAG-specific)
QUERIES_TOTAL = Counter(
    "rag_queries_total",
    "Total RAG queries",
    ["status"],
)
INGESTIONS_TOTAL = Counter(
    "rag_ingestions_total",
    "Total document ingestions",
    ["status"],
)
INGEST_CHUNKS = Counter(
    "rag_ingest_chunks_total",
    "Total chunks ingested",
)
OPENAI_TOKENS = Counter(
    "rag_openai_tokens_total",
    "OpenAI token usage",
    ["type", "model"],
)

# Pipeline step latencies (seconds)
STEP_DURATION = Histogram(
    "rag_step_duration_seconds",
    "RAG pipeline step duration",
    ["step"],
    buckets=[0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0],
)
QUERY_TOTAL_DURATION = Histogram(
    "rag_query_total_duration_seconds",
    "End-to-end query duration",
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0],
)
INGEST_DURATION = Histogram(
    "rag_ingest_duration_seconds",
    "Document ingestion duration",
    buckets=[0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0],
)

# Retrieval quality
RETRIEVAL_SCORE = Histogram(
    "rag_retrieval_score",
    "Similarity score of retrieved chunks",
    ["rank"],
    buckets=[0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1.0],
)
CHUNKS_RETRIEVED = Histogram(
    "rag_chunks_retrieved",
    "Number of chunks returned per query",
    buckets=[0, 1, 2, 3, 4, 5, 6, 8, 10],
)
CONTEXT_TOKENS = Histogram(
    "rag_context_tokens",
    "Approximate tokens sent to LLM as context",
    buckets=[100, 250, 500, 1000, 2000, 4000, 8000],
)
