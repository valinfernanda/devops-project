"""Application settings, read from environment variables (12-factor app, factor III: config).

Every setting can be overridden with an environment variable prefixed with APP_, e.g.
    APP_DATABASE_URL=postgresql+psycopg://user:pass@db:5432/taskapi
    APP_VERSION=1.0.0
    APP_LOG_LEVEL=debug

The same Docker image can therefore run in dev, test, and prod: only the environment changes.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_")

    # Default points at a local database; containers always override it.
    database_url: str = "postgresql+psycopg://taskapi:taskapi@localhost:5432/taskapi"
    version: str = "dev"
    log_level: str = "info"


@lru_cache
def get_settings() -> Settings:
    """Read settings once and reuse them (lru_cache = simple singleton)."""
    return Settings()
