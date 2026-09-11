import time
import uuid
from pathlib import Path

import chromadb
from chromadb.config import Settings as ChromaSettings
from openai import OpenAI

from config import settings
from metrics import observe_stage, record_operation, record_tokens
from models import QueryResponse, SourceChunk


def new_doc_id() -> str:
    return uuid.uuid4().hex[:12]


def chunk_text(text: str) -> list[str]:
    text = text.strip()
    if not text:
        return []

    size = settings.chunk_size
    overlap = settings.chunk_overlap
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = start + size
        chunks.append(text[start:end].strip())
        if end >= len(text):
            break
        start = max(end - overlap, start + 1)
    return [c for c in chunks if c]


def create_rag_service(
    *,
    max_attempts: int = 30,
    delay_seconds: float = 1.0,
) -> "RAGService":
    last_error: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return RAGService()
        except Exception as exc:
            last_error = exc
            if attempt >= max_attempts:
                break
            time.sleep(delay_seconds)
    raise RuntimeError(
        f"Could not connect to Chroma at {settings.chroma_host}:{settings.chroma_port}"
    ) from last_error


class RAGService:
    def __init__(self) -> None:
        self.client = OpenAI(api_key=settings.openai_api_key or "not-set")
        self.chroma = chromadb.HttpClient(
            host=settings.chroma_host,
            port=settings.chroma_port,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self.collection = self.chroma.get_or_create_collection(
            name=settings.collection_name,
            metadata={"hnsw:space": "cosine"},
        )

    def check_chroma(self) -> tuple[bool, str]:
        try:
            self.collection.count()
            return True, "connected"
        except Exception as exc:
            return False, str(exc)

    def check_openai(self) -> tuple[bool, str]:
        if not settings.openai_api_key or settings.openai_api_key.startswith("sk-your"):
            return False, "OPENAI_API_KEY not configured"
        return True, "configured"

    def stats(self) -> tuple[int, int]:
        result = self.collection.get(include=["metadatas"])
        metas = result.get("metadatas") or []
        doc_ids = {m.get("doc_id") for m in metas if m and m.get("doc_id")}
        return len(doc_ids), self.collection.count()

    def list_documents(self) -> list[dict]:
        result = self.collection.get(include=["metadatas"])
        metas = result.get("metadatas") or []
        by_doc: dict[str, dict] = {}
        for meta in metas:
            if not meta:
                continue
            doc_id = meta.get("doc_id")
            if not doc_id:
                continue
            entry = by_doc.setdefault(
                doc_id,
                {"doc_id": doc_id, "source": meta.get("source", "unknown"), "chunks": 0},
            )
            entry["chunks"] += 1
        return sorted(by_doc.values(), key=lambda x: x["source"])

    def _embed(self, texts: list[str], *, operation: str = "embed") -> list[list[float]]:
        with observe_stage("embed"):
            response = self.client.embeddings.create(
                model=settings.openai_embedding_model,
                input=texts,
            )
        usage = getattr(response, "usage", None)
        if usage is not None:
            total = getattr(usage, "total_tokens", 0) or 0
            record_tokens(operation, total=total)
        return [item.embedding for item in response.data]

    def ingest_text(self, source: str, text: str, doc_id: str | None = None) -> tuple[str, int]:
        doc_id = doc_id or new_doc_id()
        chunks = chunk_text(text)
        if not chunks:
            raise ValueError("No text content to ingest")

        with observe_stage("ingest"):
            embeddings = self._embed(chunks, operation="ingest_embed")
            ids = [f"{doc_id}:{index}" for index in range(len(chunks))]
            metadatas = [
                {"doc_id": doc_id, "source": source, "chunk_index": index}
                for index in range(len(chunks))
            ]
            self.collection.upsert(
                ids=ids,
                embeddings=embeddings,
                documents=chunks,
                metadatas=metadatas,
            )
        record_operation("ingest", "ok")
        return doc_id, len(chunks)

    def ingest_file_bytes(self, filename: str, content: bytes) -> tuple[str, int]:
        text = content.decode("utf-8", errors="replace")
        return self.ingest_text(source=filename, text=text)

    def seed_sample_docs(self, directory: Path) -> int:
        if not directory.is_dir():
            return 0
        seeded = 0
        for path in sorted(directory.glob("*")):
            if not path.is_file():
                continue
            if path.suffix.lower() not in {".txt", ".md", ".markdown"}:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            self.ingest_text(source=path.name, text=text)
            seeded += 1
        return seeded

    def query(self, question: str, top_k: int | None = None) -> QueryResponse:
        k = top_k or settings.top_k
        query_embedding = self._embed([question], operation="query_embed")[0]
        with observe_stage("retrieve"):
            results = self.collection.query(
                query_embeddings=[query_embedding],
                n_results=k,
                include=["documents", "metadatas", "distances"],
            )

        docs = (results.get("documents") or [[]])[0]
        metas = (results.get("metadatas") or [[]])[0]
        distances = (results.get("distances") or [[]])[0]

        sources: list[SourceChunk] = []
        context_parts: list[str] = []
        for index, (doc, meta, dist) in enumerate(zip(docs, metas, distances, strict=False)):
            if not doc or not meta:
                continue
            score = 1.0 - float(dist) if dist is not None else None
            chunk = SourceChunk(
                source=str(meta.get("source", "unknown")),
                doc_id=str(meta.get("doc_id", "")),
                chunk_index=int(meta.get("chunk_index", index)),
                text=doc,
                score=score,
            )
            sources.append(chunk)
            context_parts.append(f"[{chunk.source}]\n{doc}")

        context = "\n\n---\n\n".join(context_parts) if context_parts else "No relevant context found."
        system = (
            "You answer questions using only the provided context. "
            "If the context is insufficient, say you do not know."
        )
        user = f"Context:\n{context}\n\nQuestion: {question}"

        with observe_stage("chat"):
            completion = self.client.chat.completions.create(
                model=settings.openai_chat_model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                temperature=0.2,
            )
        usage = completion.usage
        if usage is not None:
            record_tokens(
                "chat",
                prompt=usage.prompt_tokens or 0,
                completion=usage.completion_tokens or 0,
                total=usage.total_tokens,
            )
        answer = completion.choices[0].message.content or ""
        record_operation("query", "ok")
        return QueryResponse(answer=answer.strip(), sources=sources)
