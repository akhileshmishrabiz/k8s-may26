import os


class Config:
    """Application settings loaded from environment variables."""

    # Secret — required in production (Flask session signing, CSRF tokens)
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-only-change-in-production")

    # Database connection string (SQLite locally, Postgres in Docker/ECS)
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DB_LINK", "sqlite:////tmp/student_portal.db"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Logging verbosity: DEBUG, INFO, WARNING, ERROR
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
