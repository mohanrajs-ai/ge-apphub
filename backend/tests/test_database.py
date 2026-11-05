"""Unit tests for PostgreSQL configuration and SQLAlchemy ORM models."""

from app import config
from app import database
from app import db_models


def test_database_and_sync_settings_defaults(monkeypatch) -> None:
    """Verifies default PostgreSQL and sync schedule settings."""
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("SYNC_ENABLED", raising=False)
    monkeypatch.delenv("SYNC_INTERVAL_SECONDS", raising=False)
    monkeypatch.delenv("SYNC_ON_STARTUP", raising=False)

    settings = config.get_settings()
    assert (
        settings.database_url
        == "postgresql+psycopg://localhost:5432/geapphub"
    )
    assert settings.sync_enabled is True
    assert settings.sync_interval_seconds == 900
    assert settings.sync_on_startup is True


def test_database_and_sync_settings_custom(monkeypatch) -> None:
    """Verifies custom PostgreSQL and sync settings from env variables."""
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    monkeypatch.setenv("SYNC_ENABLED", "false")
    monkeypatch.setenv("SYNC_INTERVAL_SECONDS", "300")
    monkeypatch.setenv("SYNC_ON_STARTUP", "false")

    settings = config.get_settings()
    assert settings.database_url == "sqlite:///:memory:"
    assert settings.sync_enabled is False
    assert settings.sync_interval_seconds == 300
    assert settings.sync_on_startup is False


def test_orm_models_crud_lifecycle(monkeypatch) -> None:
    """Verifies table creation and CRUD across all PostgreSQL ORM models."""
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    database.reset_engine_cache()
    database.init_db()

    session_gen = database.get_db_session()
    session = next(session_gen)
    try:
        user = db_models.UserRecord(
            email="mohanraj@mohanrajs.altostrat.com",
            user_id="mohanraj@mohanrajs.altostrat.com",
            display_name="Mohanraj Shanmugam",
            roles=["employee"],
            auth_source="google_oauth",
        )
        group = db_models.CloudIdentityGroupRecord(
            group_email="hr-app-01-users@mohanrajs.altostrat.com",
            group_resource_name="groups/01abc",
            display_name="HR App 01 Users",
            description="Authorized HR application group",
        )
        membership = db_models.UserGroupMembershipRecord(
            user_email="mohanraj@mohanrajs.altostrat.com",
            group_email="hr-app-01-users@mohanrajs.altostrat.com",
            membership_role="MEMBER",
        )
        app_rec = db_models.GEApplicationRecord(
            engine_id="hr-app-01_1773769422546",
            display_name="Gemini HR App",
            description="HR policy assistant",
            category="Productivity",
            department="People & HR",
            tags=["hr", "gemini-enterprise"],
            icon_name="Users",
            launch_url="https://vertexaisearch.cloud.google.com/home/cid/123",
            default_launch_url=(
                "https://vertexaisearch.cloud.google.com/home/cid/123"
            ),
            location="global",
            solution_type="SOLUTION_TYPE_SEARCH",
            industry_vertical="GENERIC",
            app_type="APP_TYPE_INTRANET",
            iam_principals=["group:hr-app-01-users@mohanrajs.altostrat.com"],
            allowed_roles=["group:hr-app-01-users@mohanrajs.altostrat.com"],
            featured=True,
        )
        binding = db_models.AppGroupBindingRecord(
            engine_id="hr-app-01_1773769422546",
            principal_type="group",
            principal_identifier="hr-app-01-users@mohanrajs.altostrat.com",
        )
        sync_run = db_models.SyncRunRecord(
            trigger_source="scheduled",
            status="completed",
            apps_synced=1,
            groups_synced=1,
            memberships_synced=1,
        )
        session.add_all(
            [user, group, membership, app_rec, binding, sync_run]
        )
        session.commit()

        saved_user = (
            session.query(db_models.UserRecord)
            .filter_by(email="mohanraj@mohanrajs.altostrat.com")
            .one()
        )
        assert saved_user.display_name == "Mohanraj Shanmugam"
        assert saved_user.roles == ["employee"]

        saved_group = (
            session.query(db_models.CloudIdentityGroupRecord)
            .filter_by(group_email="hr-app-01-users@mohanrajs.altostrat.com")
            .one()
        )
        assert saved_group.group_resource_name == "groups/01abc"

        saved_app = (
            session.query(db_models.GEApplicationRecord)
            .filter_by(engine_id="hr-app-01_1773769422546")
            .one()
        )
        assert saved_app.display_name == "Gemini HR App"
        assert saved_app.featured is True

        saved_run = session.query(db_models.SyncRunRecord).one()
        assert saved_run.status == "completed"
        assert saved_run.apps_synced == 1
        summary = saved_run.to_summary_dict()
        assert summary["trigger_source"] == "scheduled"
        assert summary["apps_synced"] == 1
    finally:
        try:
            next(session_gen)
        except StopIteration:
            pass


def test_invalid_sync_interval_falls_back_to_default(monkeypatch) -> None:
    """Verifies invalid SYNC_INTERVAL_SECONDS uses the default integer."""
    monkeypatch.setenv("SYNC_INTERVAL_SECONDS", "not-a-number")
    settings = config.get_settings()
    assert settings.sync_interval_seconds == 900


def test_unreachable_postgres_falls_back_cleanly(
    monkeypatch,
    tmp_path,
) -> None:
    """Verifies unreachable Postgres URL falls back to local SQLite engine."""
    fallback_file = tmp_path / "fallback.db"
    monkeypatch.setattr(
        database,
        "_FALLBACK_SQLITE_URL",
        f"sqlite:///{fallback_file}",
    )
    database.reset_engine_cache()
    engine = database.init_db(
        database_url="postgresql+psycopg://localhost:59999/nonexistent"
    )
    assert str(engine.url).startswith("sqlite")
    # Subsequent call hits cache
    cached_engine = database.get_engine(
        database_url="postgresql+psycopg://localhost:59999/nonexistent"
    )
    assert cached_engine is engine
    database.reset_engine_cache()
