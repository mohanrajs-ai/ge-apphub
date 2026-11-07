"""SQLAlchemy 2.0 ORM models for PostgreSQL persistence."""

import datetime
from typing import Any

import sqlalchemy
from sqlalchemy import orm


def _utc_now() -> datetime.datetime:
    """Returns the current UTC timestamp."""
    return datetime.datetime.now(datetime.timezone.utc)


class Base(orm.DeclarativeBase):
    """Base declarative class for all SQLAlchemy ORM models."""


class UserRecord(Base):
    """Persisted user profile and Cloud Identity authentication metadata."""

    __tablename__ = "users"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), unique=True, index=True, nullable=False
    )
    user_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), nullable=False
    )
    display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), default="", nullable=False
    )
    roles: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    auth_source: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="cloud_identity", nullable=False
    )
    last_login_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )
    updated_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )


class CloudIdentityGroupRecord(Base):
    """Persisted Google Cloud Identity group record."""

    __tablename__ = "cloud_identity_groups"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    group_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), unique=True, index=True, nullable=False
    )
    group_resource_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), default="", nullable=False
    )
    display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), default="", nullable=False
    )
    description: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    last_synced_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )


class UserGroupMembershipRecord(Base):
    """Persisted mapping between a user email and a Cloud Identity group."""

    __tablename__ = "user_group_memberships"
    __table_args__ = (
        sqlalchemy.UniqueConstraint(
            "user_email", "group_email", name="uq_user_group_membership"
        ),
    )

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    user_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), index=True, nullable=False
    )
    group_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), index=True, nullable=False
    )
    membership_role: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="MEMBER", nullable=False
    )
    synced_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )


class GEApplicationRecord(Base):
    """Persisted Gemini Enterprise application and enriched metadata."""

    __tablename__ = "ge_applications"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    engine_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), unique=True, index=True, nullable=False
    )
    display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), nullable=False
    )
    description: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    category: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="Productivity", nullable=False
    )
    department: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="General", nullable=False
    )
    tags: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    icon_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="Sparkles", nullable=False
    )
    launch_url: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, nullable=False
    )
    default_launch_url: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, nullable=False
    )
    location: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="global", nullable=False
    )
    solution_type: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="SOLUTION_TYPE_SEARCH", nullable=False
    )
    industry_vertical: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="GENERIC", nullable=False
    )
    app_type: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="APP_TYPE_INTRANET", nullable=False
    )
    iam_principals: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    data_store_ids: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    allowed_roles: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    featured: orm.Mapped[bool] = orm.mapped_column(
        sqlalchemy.Boolean, default=False, nullable=False
    )
    last_synced_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )


class AppGroupBindingRecord(Base):
    """Persisted IAM binding linking a GE application to a group/principal."""

    __tablename__ = "app_group_bindings"
    __table_args__ = (
        sqlalchemy.UniqueConstraint(
            "engine_id",
            "principal_type",
            "principal_identifier",
            name="uq_app_principal_binding",
        ),
    )

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    engine_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), index=True, nullable=False
    )
    principal_type: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="group", nullable=False
    )
    principal_identifier: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), index=True, nullable=False
    )
    synced_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )


class GESkillRecord(Base):
    """Persisted Gemini Enterprise skill and share approval status."""

    __tablename__ = "ge_skills"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    skill_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), unique=True, index=True, nullable=False
    )
    resource_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(512), unique=True, nullable=False
    )
    engine_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), index=True, nullable=False
    )
    app_display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), default="", nullable=False
    )
    display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), nullable=False
    )
    description: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    instruction: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    gcs_uri: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    owner_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), default="", index=True, nullable=False
    )
    state: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="DISABLED", nullable=False
    )
    sharing_scope: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="RESTRICTED", nullable=False
    )
    sharing_state: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="PENDING", nullable=False
    )
    has_active_iam_proposals: orm.Mapped[bool] = orm.mapped_column(
        sqlalchemy.Boolean, default=False, nullable=False
    )
    review_status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64),
        default="PENDING_REVIEW",
        index=True,
        nullable=False,
    )
    iam_proposals: orm.Mapped[list[dict[str, Any]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    shared_principals: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    subfiles: orm.Mapped[list[dict[str, str]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    create_time: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="", nullable=False
    )
    update_time: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="", nullable=False
    )
    last_synced_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )


class SkillWorkflowRecord(Base):
    """Persisted 5-stage skill governance & approval workflow execution."""

    __tablename__ = "skill_workflows"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    workflow_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), unique=True, index=True, nullable=False
    )
    skill_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), unique=True, index=True, nullable=False
    )
    engine_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), index=True, nullable=False
    )
    skill_display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), nullable=False
    )
    owner_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), default="", nullable=False
    )
    current_stage: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="SKILL_EVALUATION", nullable=False
    )
    status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="RUNNING", index=True, nullable=False
    )
    eval_score: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, default=0, nullable=False
    )
    eval_status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="PENDING", nullable=False
    )
    eval_report: orm.Mapped[dict[str, Any]] = orm.mapped_column(
        sqlalchemy.JSON, default=dict, nullable=False
    )
    infosec_risk_level: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="LOW", nullable=False
    )
    infosec_status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="PENDING", nullable=False
    )
    infosec_report: orm.Mapped[dict[str, Any]] = orm.mapped_column(
        sqlalchemy.JSON, default=dict, nullable=False
    )
    approval_status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="PENDING", nullable=False
    )
    approved_by: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), default="", nullable=False
    )
    approval_notes: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    approved_at: orm.Mapped[datetime.datetime | None] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), nullable=True
    )
    registry_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), default="", nullable=False
    )
    shared_in_ge: orm.Mapped[bool] = orm.mapped_column(
        sqlalchemy.Boolean, default=False, nullable=False
    )
    shared_principals: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    templatized_instruction: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    required_connectors: orm.Mapped[list[dict[str, Any]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    requested_groups: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    distribution_scope: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="SINGLE_APP", nullable=False
    )
    target_engines: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    target_app_evaluations: orm.Mapped[list[dict[str, Any]]] = (
        orm.mapped_column(sqlalchemy.JSON, default=list, nullable=False)
    )
    distributed_apps: orm.Mapped[list[dict[str, Any]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    started_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )
    updated_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
        nullable=False,
    )
    completed_at: orm.Mapped[datetime.datetime | None] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), nullable=True
    )


class SkillRegistryRecord(Base):
    """Persisted published skill in the Enterprise Skill Registry."""

    __tablename__ = "skill_registry"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    registry_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), unique=True, index=True, nullable=False
    )
    skill_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), unique=True, index=True, nullable=False
    )
    resource_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(512), nullable=False
    )
    engine_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), index=True, nullable=False
    )
    app_display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), default="", nullable=False
    )
    display_name: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(255), nullable=False
    )
    description: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    instruction: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, default="", nullable=False
    )
    version: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="1.0.0", nullable=False
    )
    owner_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), default="", nullable=False
    )
    eval_score: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, default=0, nullable=False
    )
    infosec_risk_level: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="LOW", nullable=False
    )
    approved_by: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), default="", nullable=False
    )
    shared_principals: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    required_connectors: orm.Mapped[list[dict[str, Any]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    target_engines: orm.Mapped[list[str]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    distributed_apps: orm.Mapped[list[dict[str, Any]]] = orm.mapped_column(
        sqlalchemy.JSON, default=list, nullable=False
    )
    published_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )


class WorkflowEmailRecord(Base):
    """Persisted InfoSec approval email notification and outbox record."""

    __tablename__ = "workflow_email_notifications"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    workflow_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), index=True, nullable=False
    )
    skill_id: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(128), index=True, nullable=False
    )
    recipient_email: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(320), nullable=False
    )
    subject: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(512), nullable=False
    )
    body_text: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.Text, nullable=False
    )
    delivery_status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="QUEUED_LOCAL_OUTBOX", nullable=False
    )
    created_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )


class SyncRunRecord(Base):
    """Audit log record of a scheduled or manual synchronization run."""

    __tablename__ = "sync_runs"

    id: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, primary_key=True, autoincrement=True
    )
    trigger_source: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="scheduled", nullable=False
    )
    status: orm.Mapped[str] = orm.mapped_column(
        sqlalchemy.String(64), default="running", nullable=False
    )
    apps_synced: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, default=0, nullable=False
    )
    groups_synced: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, default=0, nullable=False
    )
    memberships_synced: orm.Mapped[int] = orm.mapped_column(
        sqlalchemy.Integer, default=0, nullable=False
    )
    error_message: orm.Mapped[str | None] = orm.mapped_column(
        sqlalchemy.Text, nullable=True
    )
    started_at: orm.Mapped[datetime.datetime] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), default=_utc_now, nullable=False
    )
    completed_at: orm.Mapped[datetime.datetime | None] = orm.mapped_column(
        sqlalchemy.DateTime(timezone=True), nullable=True
    )

    def to_summary_dict(self) -> dict[str, Any]:
        """Serializes the sync run record into a dictionary."""
        return {
            "id": self.id,
            "trigger_source": self.trigger_source,
            "status": self.status,
            "apps_synced": self.apps_synced,
            "groups_synced": self.groups_synced,
            "memberships_synced": self.memberships_synced,
            "error_message": self.error_message,
            "started_at": (
                self.started_at.isoformat() if self.started_at else None
            ),
            "completed_at": (
                self.completed_at.isoformat() if self.completed_at else None
            ),
        }
