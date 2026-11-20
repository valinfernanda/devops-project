"""Database connection (SQLAlchemy 2.x)."""

from collections.abc import Iterator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    """Parent class for all ORM models (tables)."""


# create_engine() does NOT connect yet; it connects lazily on first use.
# pool_pre_ping=True: test a pooled connection before using it, so a database
# restart doesn't cause "connection closed" errors in the app.
engine = create_engine(get_settings().database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_session() -> Iterator[Session]:
    """FastAPI dependency: one session per request, always closed afterwards."""
    with SessionLocal() as session:
        yield session


def check_database() -> bool:
    """Used by the readiness probe: can we run a trivial query right now?"""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
