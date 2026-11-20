"""Alembic environment: tells Alembic how to connect and which tables exist."""

from alembic import context
from sqlalchemy import create_engine, pool

from taskapi import models  # noqa: F401  (importing registers the tables on Base.metadata)
from taskapi.config import get_settings
from taskapi.db import Base

target_metadata = Base.metadata
database_url = get_settings().database_url


def run_migrations_offline() -> None:
    """Generate SQL without connecting (alembic upgrade head --sql)."""
    context.configure(url=database_url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Connect to the database and apply migrations."""
    engine = create_engine(database_url, poolclass=pool.NullPool)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
