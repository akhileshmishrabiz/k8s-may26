from pydantic import BaseModel, ConfigDict, Field


class IngestRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "source": "runbook",
                    "text": "If a pod is CrashLoopBackOff, check logs with kubectl logs and verify env vars.",
                }
            ]
        }
    )

    text: str = Field(..., min_length=1, description="Raw text to chunk and store in the vector DB")
    source: str = Field(default="manual", description="Label shown in citations")
    doc_id: str | None = Field(default=None, description="Optional custom document id")


class IngestResponse(BaseModel):
    doc_id: str
    source: str
    chunks: int
    message: str


class QueryRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"question": "What is a Kubernetes Pod?"},
                {"question": "Why is my pod stuck in Pending?", "top_k": 4},
            ]
        }
    )

    question: str = Field(..., min_length=1, description="Question to answer from ingested documents")
    top_k: int | None = Field(default=None, ge=1, le=20, description="Number of chunks to retrieve")


class ChatRequest(BaseModel):
    """Demo-friendly request body for Swagger (same as /query)."""

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"message": "What is a Kubernetes Pod?"},
                {"message": "How do I debug CrashLoopBackOff?", "top_k": 4},
            ]
        }
    )

    message: str = Field(..., min_length=1, description="Your chat message / question")
    top_k: int | None = Field(default=None, ge=1, le=20, description="Retrieved context chunks (default from config)")


class SourceChunk(BaseModel):
    source: str
    doc_id: str
    chunk_index: int
    text: str
    score: float | None = None


class QueryResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "answer": "A Pod is the smallest deployable unit in Kubernetes.",
                    "sources": [
                        {
                            "source": "kubernetes-faq.txt",
                            "doc_id": "abc123",
                            "chunk_index": 0,
                            "text": "What is a Kubernetes Pod? A Pod is...",
                            "score": 0.92,
                        }
                    ],
                }
            ]
        }
    )

    answer: str = Field(..., description="LLM answer grounded in retrieved chunks")
    sources: list[SourceChunk] = Field(default_factory=list, description="Chunks used as context")


class ChatResponse(BaseModel):
    reply: str = Field(..., description="Assistant reply")
    sources: list[SourceChunk] = Field(default_factory=list, description="Retrieved context chunks")


class HealthResponse(BaseModel):
    status: str
    documents: int
    chunks: int
    chroma: str
    openai: str


class UploadResponse(BaseModel):
    doc_id: str
    source: str
    chunks: int
    message: str
