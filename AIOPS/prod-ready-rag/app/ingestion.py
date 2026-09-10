import re
import uuid
from io import BytesIO
from pathlib import Path

from pypdf import PdfReader

from config import settings


def load_text_from_bytes(filename: str, content: bytes) -> str:
    suffix = Path(filename).suffix.lower()
    if suffix in {".txt", ".md", ".markdown"}:
        return content.decode("utf-8", errors="replace")
    if suffix == ".pdf":
        reader = PdfReader(BytesIO(content))
        pages = [page.extract_text() or "" for page in reader.pages]
        return "\n\n".join(pages)
    raise ValueError(f"Unsupported file type: {suffix}. Use .txt, .md, or .pdf")


def load_text_from_path(path: Path) -> str:
    return load_text_from_bytes(path.name, path.read_bytes())


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def chunk_text(text: str) -> list[str]:
    text = normalize_text(text)
    if not text:
        return []

    chunks: list[str] = []
    start = 0
    size = settings.chunk_size
    overlap = settings.chunk_overlap

    while start < len(text):
        end = start + size
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= len(text):
            break
        start = max(end - overlap, start + 1)

    return chunks


def new_doc_id() -> str:
    return str(uuid.uuid4())
