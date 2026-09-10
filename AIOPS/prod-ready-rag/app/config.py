from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    openai_embedding_model: str = "text-embedding-3-small"
    chroma_host: str = "chroma"
    chroma_port: int = 8000
    collection_name: str = "rag_documents"
    chunk_size: int = 800
    chunk_overlap: int = 150
    top_k: int = 4

    # OpenTelemetry
    otel_service_name: str = "rag-api"
    otel_exporter_endpoint: str = "http://jaeger:4317"

    # Langfuse (optional — get free keys at https://cloud.langfuse.com)
    langfuse_public_key: str = ""
    langfuse_secret_key: str = ""
    langfuse_host: str = "https://cloud.langfuse.com"

    @property
    def langfuse_enabled(self) -> bool:
        return bool(self.langfuse_public_key and self.langfuse_secret_key)


settings = Settings()
