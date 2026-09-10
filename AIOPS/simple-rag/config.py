from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    openai_api_key: str = ""
    openai_embedding_model: str = "text-embedding-3-small"
    openai_chat_model: str = "gpt-4o-mini"

    chroma_host: str = "localhost"
    chroma_port: int = 8000
    collection_name: str = "simple_rag"

    chunk_size: int = 800
    chunk_overlap: int = 100
    top_k: int = 4
    seed_sample_docs: bool = True


settings = Settings()
