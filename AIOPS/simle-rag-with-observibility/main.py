import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from prometheus_fastapi_instrumentator import Instrumentator

from config import settings
from models import (
    ChatRequest,
    ChatResponse,
    HealthResponse,
    IngestRequest,
    IngestResponse,
    QueryRequest,
    QueryResponse,
    UploadResponse,
)
from rag import RAGService, create_rag_service

SAMPLE_DIR = Path(__file__).parent / "sample_docs"
STATIC_DIR = Path(__file__).parent / "static"
rag: RAGService | None = None

OPENAPI_TAGS = [
    {
        "name": "Demo — Chat",
        "description": "Ask questions against ingested knowledge. Use **Try it out** on `POST /chat`.",
    },
    {
        "name": "Demo — Upload",
        "description": "Add documents to the vector store. Upload `.txt` or `.md` files via **Try it out**.",
    },
    {"name": "Documents", "description": "List and ingest text without a file upload."},
    {"name": "System", "description": "Health and readiness."},
]

DEMO_DESCRIPTION = """
### Quick demo (Swagger UI)

1. Open **Demo — Upload** → `POST /documents/upload` → **Try it out** → choose a `.txt` / `.md` file → **Execute**.
2. Open **Demo — Chat** → `POST /chat` → **Try it out** → enter a `message` → **Execute**.
3. Optional: **Documents** → `GET /documents` to see what is indexed.

Swagger UI: [/docs](/docs) · OpenAPI JSON: [/openapi.json](/openapi.json)
"""


def get_rag() -> RAGService:
    if rag is None:
        raise HTTPException(status_code=503, detail="RAG service is not ready yet")
    return rag


def require_openai(service: RAGService) -> None:
    openai_ok, openai_detail = service.check_openai()
    if not openai_ok:
        raise HTTPException(status_code=500, detail=openai_detail)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global rag
    rag = await asyncio.to_thread(create_rag_service)

    openai_ok, _ = rag.check_openai()
    if settings.seed_sample_docs and openai_ok:
        try:
            seeded = await asyncio.to_thread(rag.seed_sample_docs, SAMPLE_DIR)
            if seeded:
                print(f"Seeded {seeded} sample document(s) from {SAMPLE_DIR}")
        except Exception as exc:
            print(f"Sample doc seed skipped: {exc}")
    elif settings.seed_sample_docs and not openai_ok:
        print("Sample doc seed skipped: OPENAI_API_KEY is not configured")

    yield


app = FastAPI(
    title="Simple RAG Demo",
    version="1.0.0",
    description=DEMO_DESCRIPTION,
    openapi_tags=OPENAPI_TAGS,
    swagger_ui_parameters={
        "docExpansion": "list",
        "defaultModelsExpandDepth": 2,
        "tryItOutEnabled": True,
    },
    lifespan=lifespan,
)

Instrumentator(
    should_group_status_codes=True,
    should_ignore_untemplated=True,
    excluded_handlers=["/metrics"],
).instrument(app).expose(app, include_in_schema=False)


@app.get("/", include_in_schema=False)
async def ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health", response_model=HealthResponse, tags=["System"])
async def health() -> HealthResponse:
    service = get_rag()
    doc_count, chunk_count = service.stats()
    chroma_ok, chroma_detail = service.check_chroma()
    openai_ok, openai_detail = service.check_openai()
    status = "ok" if chroma_ok and openai_ok else "degraded"
    return HealthResponse(
        status=status,
        documents=doc_count,
        chunks=chunk_count,
        chroma=chroma_detail if chroma_ok else f"error: {chroma_detail}",
        openai=openai_detail if openai_ok else f"error: {openai_detail}",
    )


@app.get("/documents", tags=["Documents"])
async def list_documents():
    """List ingested documents and chunk counts."""
    return get_rag().list_documents()


@app.post("/chat", response_model=ChatResponse, tags=["Demo — Chat"])
async def chat(request: ChatRequest) -> ChatResponse:
    """
    **Demo chat endpoint** — send a `message`, get a `reply` plus cited `sources`.

    Same retrieval + OpenAI flow as `/query`, with a chat-shaped request/response for Swagger demos.
    """
    service = get_rag()
    require_openai(service)
    try:
        result = service.query(request.message, request.top_k)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Chat failed: {exc}") from exc
    return ChatResponse(reply=result.answer, sources=result.sources)


@app.post("/query", response_model=QueryResponse, tags=["Demo — Chat"])
async def query_documents(request: QueryRequest) -> QueryResponse:
    """Query ingested documents (alias of chat logic with `question` field)."""
    service = get_rag()
    require_openai(service)
    try:
        return service.query(request.question, request.top_k)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Query failed: {exc}") from exc


@app.post(
    "/documents/upload",
    response_model=UploadResponse,
    tags=["Demo — Upload"],
    summary="Upload a document file",
)
async def upload_document(
    file: UploadFile = File(
        ...,
        description="Knowledge file to ingest (.txt, .md). Content is chunked and embedded into Chroma.",
    ),
) -> UploadResponse:
    """
    **Demo upload** — use **Try it out**, pick a file, then **Execute**.

    After upload, use `POST /chat` to ask questions about the file.
    """
    service = get_rag()
    require_openai(service)
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty file")
    try:
        doc_id, chunks = service.ingest_file_bytes(file.filename or "upload.txt", content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {exc}") from exc
    return UploadResponse(
        doc_id=doc_id,
        source=file.filename or "upload.txt",
        chunks=chunks,
        message=f"Ingested {chunks} chunk(s)",
    )


@app.post("/ingest", response_model=IngestResponse, tags=["Documents"])
async def ingest_text(body: IngestRequest) -> IngestResponse:
    """Ingest plain text JSON (no file upload)."""
    service = get_rag()
    require_openai(service)
    try:
        doc_id, chunks = service.ingest_text(body.source, body.text, body.doc_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {exc}") from exc
    return IngestResponse(
        doc_id=doc_id,
        source=body.source,
        chunks=chunks,
        message=f"Ingested {chunks} chunk(s)",
    )
