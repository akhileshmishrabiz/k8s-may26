from __future__ import annotations

from typing import Any

from config import settings
from observability.logging_config import get_logger

logger = get_logger(__name__)

_langfuse = None


def get_langfuse():
    global _langfuse
    if _langfuse is not None:
        return _langfuse

    if not settings.langfuse_enabled:
        _langfuse = _NoOpLangfuse()
        return _langfuse

    try:
        from langfuse import Langfuse

        _langfuse = Langfuse(
            public_key=settings.langfuse_public_key,
            secret_key=settings.langfuse_secret_key,
            host=settings.langfuse_host,
        )
        logger.info("langfuse_initialized", host=settings.langfuse_host)
    except Exception as exc:
        logger.warning("langfuse_init_failed", error=str(exc))
        _langfuse = _NoOpLangfuse()

    return _langfuse


class _NoOpLangfuse:
    def trace(self, **kwargs: Any):
        return _NoOpTrace()

    def flush(self) -> None:
        pass


class _NoOpTrace:
    def span(self, **kwargs: Any):
        return _NoOpSpan()

    def generation(self, **kwargs: Any):
        return _NoOpSpan()

    def update(self, **kwargs: Any) -> None:
        pass


class _NoOpSpan:
    def end(self, **kwargs: Any) -> None:
        pass

    def update(self, **kwargs: Any) -> None:
        pass
