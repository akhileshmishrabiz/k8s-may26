from pydantic import BaseModel, Field


class QueryRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    top_k: int | None = Field(default=None, ge=1, le=10)


class SourceChunk(BaseModel):
    doc_id: str
    source: str
    chunk_index: int
    text: str
    score: float


class QueryResponse(BaseModel):
    answer: str
    sources: list[SourceChunk]


class DocumentInfo(BaseModel):
    doc_id: str
    source: str
    chunks: int


class UploadResponse(BaseModel):
    doc_id: str
    source: str
    chunks: int
    message: str


class DependencyStatus(BaseModel):
    name: str
    status: str
    detail: str = ""


class HealthResponse(BaseModel):
    status: str
    documents: int
    chunks: int
    dependencies: list[DependencyStatus] = []
