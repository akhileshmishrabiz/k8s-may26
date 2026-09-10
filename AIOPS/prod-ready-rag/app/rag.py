import logging
import time
from pathlib import Path

import chromadb
from chromadb.config import Settings as ChromaSettings
from openai import OpenAI

from config import settings
from ingestion import chunk_text, load_text_from_bytes, load_text_from_path, new_doc_id
from models import DocumentInfo, QueryResponse, SourceChunk
from observability.langfuse_client import get_langfuse
from observability.logging_config import get_logger, request_id_var
from observability.metrics import (
    CHUNKS_RETRIEVED,
    CONTEXT_TOKENS,
    INGEST_CHUNKS,
    INGEST_DURATION,
    INGESTIONS_TOTAL,
    OPENAI_TOKENS,
    QUERIES_TOTAL,
    QUERY_TOTAL_DURATION,
    RETRIEVAL_SCORE,
    STEP_DURATION,
)
from observability.tracing import get_tracer

logger = get_logger(__name__)
tracer = get_tracer(__name__)
py_logger = logging.getLogger(__name__)


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
        self.langfuse = get_langfuse()

    def check_chroma(self) -> tuple[bool, str]:
        try:
            self.collection.count()
            return True, "connected"
        except Exception as exc:
            return False, str(exc)

    def check_openai(self) -> tuple[bool, str]:
        if not settings.openai_api_key or settings.openai_api_key.startswith("sk-your"):
            return False, "API key not configured"
        return True, "configured"

    def _embed(self, texts: list[str], step: str = "embed") -> tuple[list[list[float]], int]:
        with tracer.start_as_current_span(f"openai.{step}") as span:
            span.set_attribute("texts.count", len(texts))
            span.set_attribute("model", settings.openai_embedding_model)
            start = time.perf_counter()
            response = self.client.embeddings.create(
                model=settings.openai_embedding_model,
                input=texts,
            )
            duration = time.perf_counter() - start
            tokens = response.usage.total_tokens if response.usage else 0
            STEP_DURATION.labels(step=step).observe(duration)
            OPENAI_TOKENS.labels(type="embedding", model=settings.openai_embedding_model).inc(tokens)
            span.set_attribute("tokens", tokens)
            span.set_attribute("duration_ms", round(duration * 1000, 2))
            return [item.embedding for item in response.data], tokens

    def ingest_text(self, source: str, text: str, doc_id: str | None = None) -> tuple[str, int]:
        doc_id = doc_id or new_doc_id()
        chunks = chunk_text(text)
        if not chunks:
            raise ValueError("No text content found in document")

        lf_trace = self.langfuse.trace(
            name="ingest-document",
            input={"source": source, "text_length": len(text)},
            metadata={"request_id": request_id_var.get()},
        )

        with tracer.start_as_current_span("ingest.document") as span:
            span.set_attribute("source", source)
            span.set_attribute("chunks", len(chunks))

            embed_span = lf_trace.span(name="embed-chunks", input={"chunk_count": len(chunks)})
            embeddings, tokens = self._embed(chunks, step="embed_ingest")
            embed_span.end(output={"tokens": tokens, "chunks": len(chunks)})

            store_span = lf_trace.span(name="chroma-store")
            ids = [f"{doc_id}:{index}" for index in range(len(chunks))]
            metadatas = [
                {"doc_id": doc_id, "source": source, "chunk_index": index}
                for index in range(len(chunks))
            ]
            self.collection.add(
                ids=ids,
                documents=chunks,
                embeddings=embeddings,
                metadatas=metadatas,
            )
            store_span.end(output={"stored": len(chunks)})

        INGEST_CHUNKS.inc(len(chunks))
        lf_trace.update(output={"doc_id": doc_id, "chunks": len(chunks)})
        return doc_id, len(chunks)

    def ingest_file_bytes(self, filename: str, content: bytes) -> tuple[str, int]:
        text = load_text_from_bytes(filename, content)
        return self.ingest_text(source=filename, text=text)

    def ingest_path(self, path: Path) -> tuple[str, int]:
        text = load_text_from_path(path)
        return self.ingest_text(source=path.name, text=text)

    def list_documents(self) -> list[DocumentInfo]:
        result = self.collection.get(include=["metadatas"])
        counts: dict[str, dict[str, str | int]] = {}
        for metadata in result.get("metadatas") or []:
            if not metadata:
                continue
            doc_id = metadata["doc_id"]
            if doc_id not in counts:
                counts[doc_id] = {"source": metadata["source"], "chunks": 0}
            counts[doc_id]["chunks"] = int(counts[doc_id]["chunks"]) + 1

        return [
            DocumentInfo(doc_id=doc_id, source=str(info["source"]), chunks=int(info["chunks"]))
            for doc_id, info in sorted(counts.items(), key=lambda item: str(item[1]["source"]))
        ]

    def stats(self) -> tuple[int, int]:
        docs = self.list_documents()
        return len(docs), self.collection.count()

    def query(self, question: str, top_k: int | None = None) -> QueryResponse:
        k = top_k or settings.top_k
        total_start = time.perf_counter()
        request_id = request_id_var.get()

        lf_trace = self.langfuse.trace(
            name="rag-query",
            input={"question": question, "top_k": k},
            metadata={"request_id": request_id},
        )

        if self.collection.count() == 0:
            QUERIES_TOTAL.labels(status="empty").inc()
            return QueryResponse(
                answer="No documents have been indexed yet. Upload a file or wait for sample docs to load.",
                sources=[],
            )

        timings: dict[str, float] = {}

        # Step 1: Embed query
        with tracer.start_as_current_span("rag.embed_query") as span:
            lf_embed = lf_trace.span(name="embed-query", input={"question": question})
            t0 = time.perf_counter()
            embeddings, embed_tokens = self._embed([question], step="embed_query")
            query_embedding = embeddings[0]
            timings["embed_ms"] = round((time.perf_counter() - t0) * 1000, 2)
            span.set_attribute("duration_ms", timings["embed_ms"])
            lf_embed.end(output={"tokens": embed_tokens, "duration_ms": timings["embed_ms"]})

        # Step 2: Retrieve from Chroma
        with tracer.start_as_current_span("rag.retrieve") as span:
            lf_retrieve = lf_trace.span(name="chroma-retrieve", input={"top_k": k})
            t0 = time.perf_counter()
            results = self.collection.query(
                query_embeddings=[query_embedding],
                n_results=k,
                include=["documents", "metadatas", "distances"],
            )
            timings["retrieve_ms"] = round((time.perf_counter() - t0) * 1000, 2)
            STEP_DURATION.labels(step="retrieve").observe(time.perf_counter() - t0)
            span.set_attribute("duration_ms", timings["retrieve_ms"])

        documents = results["documents"][0] if results["documents"] else []
        metadatas = results["metadatas"][0] if results["metadatas"] else []
        distances = results["distances"][0] if results["distances"] else []

        sources: list[SourceChunk] = []
        context_blocks: list[str] = []
        scores: list[float] = []
        for index, (doc, metadata, distance) in enumerate(
            zip(documents, metadatas, distances, strict=False)
        ):
            score = round(1 - distance, 4)
            scores.append(score)
            RETRIEVAL_SCORE.labels(rank=str(index + 1)).observe(score)
            sources.append(
                SourceChunk(
                    doc_id=metadata["doc_id"],
                    source=metadata["source"],
                    chunk_index=metadata["chunk_index"],
                    text=doc,
                    score=score,
                )
            )
            context_blocks.append(
                f"[Source {index + 1}: {metadata['source']} | chunk {metadata['chunk_index']} | score {score}]\n{doc}"
            )

        CHUNKS_RETRIEVED.observe(len(sources))
        lf_retrieve.end(output={
            "chunks": len(sources),
            "scores": scores,
            "sources": [s.source for s in sources],
            "duration_ms": timings["retrieve_ms"],
        })

        context = "\n\n---\n\n".join(context_blocks)
        approx_context_tokens = len(context.split())
        CONTEXT_TOKENS.observe(approx_context_tokens)

        prompt = (
            "You are a helpful assistant. Answer the user's question using ONLY the provided context. "
            "If the context does not contain enough information, say you don't know based on the indexed documents. "
            "Keep answers concise and practical.\n\n"
            f"Context:\n{context}\n\nQuestion: {question}"
        )

        # Step 3: LLM generation
        with tracer.start_as_current_span("rag.generate") as span:
            lf_gen = lf_trace.generation(
                name="openai-chat",
                model=settings.openai_model,
                input=prompt,
                metadata={"retrieval_scores": scores},
            )
            t0 = time.perf_counter()
            completion = self.client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": "You answer questions from retrieved document context."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.2,
            )
            llm_duration = time.perf_counter() - t0
            timings["llm_ms"] = round(llm_duration * 1000, 2)
            STEP_DURATION.labels(step="generate").observe(llm_duration)
            span.set_attribute("duration_ms", timings["llm_ms"])
            span.set_attribute("model", settings.openai_model)

            usage = completion.usage
            if usage:
                OPENAI_TOKENS.labels(type="prompt", model=settings.openai_model).inc(usage.prompt_tokens)
                OPENAI_TOKENS.labels(type="completion", model=settings.openai_model).inc(
                    usage.completion_tokens
                )
                lf_gen.end(
                    output=completion.choices[0].message.content,
                    usage={
                        "input": usage.prompt_tokens,
                        "output": usage.completion_tokens,
                    },
                )
            else:
                lf_gen.end(output=completion.choices[0].message.content)

        answer = completion.choices[0].message.content or "No answer generated."
        timings["total_ms"] = round((time.perf_counter() - total_start) * 1000, 2)
        QUERY_TOTAL_DURATION.observe(time.perf_counter() - total_start)
        QUERIES_TOTAL.labels(status="success").inc()

        lf_trace.update(output={"answer": answer, "sources_count": len(sources)})

        logger.info(
            "rag_query_complete",
            request_id=request_id,
            question_length=len(question),
            top_k=k,
            chunks_retrieved=len(sources),
            top_score=scores[0] if scores else 0,
            avg_score=round(sum(scores) / len(scores), 4) if scores else 0,
            context_tokens=approx_context_tokens,
            **timings,
        )

        self.langfuse.flush()
        return QueryResponse(answer=answer, sources=sources)

    def seed_sample_docs(self, sample_dir: Path) -> int:
        if not sample_dir.exists():
            return 0

        existing_sources = {doc.source for doc in self.list_documents()}
        seeded = 0
        for path in sorted(sample_dir.iterdir()):
            if not path.is_file() or path.suffix.lower() not in {".txt", ".md", ".markdown", ".pdf"}:
                continue
            if path.name in existing_sources:
                continue
            try:
                doc_id, chunk_count = self.ingest_path(path)
                py_logger.info("Seeded %s as %s (%s chunks)", path.name, doc_id, chunk_count)
                seeded += 1
            except Exception:
                py_logger.exception("Failed to seed %s", path.name)
        return seeded
