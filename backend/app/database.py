"""Database engine and session management for PostgreSQL / SQLAlchemy."""

import contextlib
import logging
import os
import pathlib
from collections import abc

import sqlalchemy
from sqlalchemy import orm
from sqlalchemy import pool

from app import config
from app import db_models

LOGGER = logging.getLogger(__name__)
_ENGINE_CACHE: dict[str, sqlalchemy.Engine] = {}
_FALLBACK_SQLITE_URL = (
    "sqlite:///"
    + str(pathlib.Path(__file__).resolve().parents[1] / "geapphub_local.db")
)


def reset_engine_cache() -> None:
    """Clears cached SQLAlchemy engines (used in testing)."""
    for eng in _ENGINE_CACHE.values():
        eng.dispose()
    _ENGINE_CACHE.clear()


def _create_sqlalchemy_engine(database_url: str) -> sqlalchemy.Engine:
    """Creates a SQLAlchemy Engine for the given database URL.

    Args:
        database_url: SQLAlchemy connection string.

    Returns:
        Configured SQLAlchemy Engine.
    """
    if database_url.startswith("sqlite"):
        connect_args = {"check_same_thread": False}
        if ":memory:" in database_url:
            return sqlalchemy.create_engine(
                database_url,
                connect_args=connect_args,
                poolclass=pool.StaticPool,
            )
        return sqlalchemy.create_engine(
            database_url,
            connect_args=connect_args,
        )
    return sqlalchemy.create_engine(
        database_url,
        pool_pre_ping=True,
    )


def get_engine(database_url: str | None = None) -> sqlalchemy.Engine:
    """Returns or initializes a cached SQLAlchemy engine.

    If a PostgreSQL connection is unreachable in local/test environments,
    falls back cleanly to a local SQLite database so the service remains
    operational while logging a warning.

    Args:
        database_url: Optional override connection URL.

    Returns:
        Active SQLAlchemy Engine.
    """
    resolved_url = database_url
    if not resolved_url:
        settings = config.get_settings()
        if settings.use_mock_data and "DATABASE_URL" not in os.environ:
            resolved_url = "sqlite:///:memory:"
        else:
            resolved_url = settings.database_url
    if resolved_url in _ENGINE_CACHE:
        return _ENGINE_CACHE[resolved_url]

    engine = _create_sqlalchemy_engine(resolved_url)
    if not resolved_url.startswith("sqlite"):
        try:
            with engine.connect() as conn:
                conn.execute(sqlalchemy.text("SELECT 1"))
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.warning(
                "PostgreSQL at %s unreachable (%s); using local fallback %s.",
                resolved_url,
                exc,
                _FALLBACK_SQLITE_URL,
            )
            engine.dispose()
            engine = _create_sqlalchemy_engine(_FALLBACK_SQLITE_URL)
    _ENGINE_CACHE[resolved_url] = engine
    return engine


def _ensure_schema_migrations(engine: sqlalchemy.Engine) -> None:
    """Adds newly introduced columns to existing tables if missing."""
    migrations = [
        ("ge_applications", "data_store_ids", "JSON DEFAULT '[]'"),
        ("skill_workflows", "templatized_instruction", "TEXT DEFAULT ''"),
        ("skill_workflows", "required_connectors", "JSON DEFAULT '[]'"),
        ("skill_workflows", "requested_groups", "JSON DEFAULT '[]'"),
        (
            "skill_workflows",
            "distribution_scope",
            "VARCHAR(64) DEFAULT 'SINGLE_APP'",
        ),
        ("skill_workflows", "target_engines", "JSON DEFAULT '[]'"),
        ("skill_workflows", "target_app_evaluations", "JSON DEFAULT '[]'"),
        ("skill_workflows", "distributed_apps", "JSON DEFAULT '[]'"),
        ("skill_registry", "required_connectors", "JSON DEFAULT '[]'"),
        ("skill_registry", "target_engines", "JSON DEFAULT '[]'"),
        ("skill_registry", "distributed_apps", "JSON DEFAULT '[]'"),
        ("ge_skills", "sub_skills", "JSON DEFAULT '[]'"),
        ("skill_workflows", "sub_skills", "JSON DEFAULT '[]'"),
        ("skill_registry", "sub_skills", "JSON DEFAULT '[]'"),
    ]
    inspector = sqlalchemy.inspect(engine)
    existing_tables = set(inspector.get_table_names())
    with engine.begin() as conn:
        for table_name, col_name, col_def in migrations:
            if table_name not in existing_tables:
                continue
            cols = {c["name"] for c in inspector.get_columns(table_name)}
            if col_name not in cols:
                conn.execute(
                    sqlalchemy.text(
                        f"ALTER TABLE {table_name} ADD COLUMN {col_name} "
                        f"{col_def}"
                    )
                )


def init_db(database_url: str | None = None) -> sqlalchemy.Engine:
    """Creates all database tables if they do not already exist.

    Args:
        database_url: Optional override connection URL.

    Returns:
        Initialized SQLAlchemy Engine.
    """
    engine = get_engine(database_url=database_url)
    db_models.Base.metadata.create_all(bind=engine)
    _ensure_schema_migrations(engine)
    return engine


@contextlib.contextmanager
def session_scope(
    database_url: str | None = None,
) -> abc.Iterator[orm.Session]:
    """Provides a transactional scope around a series of ORM operations.

    Args:
        database_url: Optional override connection URL.

    Yields:
        Active SQLAlchemy Session.
    """
    engine = init_db(database_url=database_url)
    session_factory = orm.sessionmaker(
        bind=engine,
        autocommit=False,
        autoflush=False,
        expire_on_commit=False,
    )
    session = session_factory()
    try:
        yield session
    finally:
        session.close()


def get_db_session() -> abc.Iterator[orm.Session]:
    """FastAPI dependency that yields a SQLAlchemy database session.

    Yields:
        Active SQLAlchemy Session.
    """
    with session_scope() as session:
        yield session
