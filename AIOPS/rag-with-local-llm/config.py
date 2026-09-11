from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ollama_base_url: str = "http://localhost:11434"
    ollama_chat_model: str = "gemma2:2b"
    ollama_embedding_model: str = "nomic-embed-text"

    chroma_host: str = "localhost"
    chroma_port: int = 8000
    collection_name: str = "simple_rag"

    chunk_size: int = 800
    chunk_overlap: int = 100
    top_k: int = 4
    seed_sample_docs: bool = True


settings = Settings()
