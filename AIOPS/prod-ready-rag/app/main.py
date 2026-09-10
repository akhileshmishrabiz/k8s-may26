import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from prometheus_fastapi_instrumentator import Instrumentator

from config import settings
from models import DependencyStatus, HealthResponse, QueryRequest, QueryResponse, UploadResponse
from observability.logging_config import get_logger, setup_logging
from observability.metrics import INGEST_DURATION, INGESTIONS_TOTAL
from observability.middleware import ObservabilityMiddleware
from observability.tracing import setup_tracing
from rag import RAGService

setup_logging()
logger = get_logger(__name__)

STATIC_DIR = Path(__file__).parent / "static"
SAMPLE_DIR = Path(__file__).parent / "sample_docs"

rag = RAGService()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if not settings.openai_api_key:
        logger.warning("openai_key_missing")
    seeded = rag.seed_sample_docs(SAMPLE_DIR)
    if seeded:
        logger.info("sample_docs_seeded", count=seeded)
    yield
    rag.langfuse.flush()


app = FastAPI(title="RAG Demo", version="2.0.0", lifespan=lifespan)
app.add_middleware(ObservabilityMiddleware)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")
setup_tracing(app)


@app.get("/")
async def ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    doc_count, chunk_count = rag.stats()

    chroma_ok, chroma_detail = rag.check_chroma()
    openai_ok, openai_detail = rag.check_openai()

    dependencies = [
        DependencyStatus(name="chroma", status="ok" if chroma_ok else "error", detail=chroma_detail),
        DependencyStatus(name="openai", status="ok" if openai_ok else "error", detail=openai_detail),
        DependencyStatus(
            name="langfuse",
            status="ok" if settings.langfuse_enabled else "disabled",
            detail="configured" if settings.langfuse_enabled else "set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY",
        ),
    ]

    overall = "ok" if chroma_ok and openai_ok else "degraded"
    return HealthResponse(
        status=overall,
        documents=doc_count,
        chunks=chunk_count,
        dependencies=dependencies,
    )


@app.get("/documents")
async def list_documents():
    return rag.list_documents()


@app.post("/documents/upload", response_model=UploadResponse)
async def upload_document(file: UploadFile = File(...)) -> UploadResponse:
    if not settings.openai_api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not configured")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty file")

    start = time.perf_counter()
    try:
        doc_id, chunks = rag.ingest_file_bytes(file.filename or "upload.txt", content)
        INGESTIONS_TOTAL.labels(status="success").inc()
        INGEST_DURATION.observe(time.perf_counter() - start)
        logger.info(
            "ingest_complete",
            source=file.filename,
            doc_id=doc_id,
            chunks=chunks,
            duration_ms=round((time.perf_counter() - start) * 1000, 2),
        )
    except ValueError as exc:
        INGESTIONS_TOTAL.labels(status="error").inc()
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        INGESTIONS_TOTAL.labels(status="error").inc()
        logger.exception("ingest_failed", source=file.filename)
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {exc}") from exc

    return UploadResponse(
        doc_id=doc_id,
        source=file.filename or "upload.txt",
        chunks=chunks,
        message=f"Ingested {chunks} chunk(s)",
    )


@app.post("/query", response_model=QueryResponse)
async def query_documents(request: QueryRequest) -> QueryResponse:
    if not settings.openai_api_key:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not configured")

    try:
        return rag.query(request.question, top_k=request.top_k)
    except Exception as exc:
        logger.exception("query_failed")
        raise HTTPException(status_code=500, detail=f"Query failed: {exc}") from exc


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
