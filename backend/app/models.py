"""Pydantic data models for the Gemini Enterprise AppHub backend."""

from typing import Any

import pydantic


class UserContext(pydantic.BaseModel):
    """Represents the authenticated user identity and resolved roles."""

    email: str
    user_id: str
    roles: list[str]
    groups: list[str] = pydantic.Field(default_factory=list)
    auth_source: str


class DiscoveredEngine(pydantic.BaseModel):
    """Represents a raw Gemini Enterprise / Discovery Engine record."""

    engine_id: str
    display_name: str
    location: str
    solution_type: str = "SOLUTION_TYPE_SEARCH"
    industry_vertical: str = "GENERIC"
    app_type: str = "APP_TYPE_INTRANET"
    default_launch_url: str
    iam_principals: list[str] = pydantic.Field(default_factory=list)


class AppEnrichmentMetadata(pydantic.BaseModel):
    """Represents Firestore enrichment metadata for a GE application."""

    engine_id: str
    description: str = ""
    category: str = "Productivity"
    department: str = "General"
    tags: list[str] = pydantic.Field(default_factory=list)
    icon_name: str = "Sparkles"
    launch_url: str | None = None
    allowed_roles: list[str] = pydantic.Field(default_factory=lambda: ["*"])
    featured: bool = False


class CatalogApplication(pydantic.BaseModel):
    """Represents an enriched Gemini Enterprise application in the catalog."""

    engine_id: str
    display_name: str
    description: str
    category: str
    department: str
    tags: list[str]
    icon_name: str
    launch_url: str
    location: str
    solution_type: str
    allowed_roles: list[str]
    featured: bool = False


class CatalogResponse(pydantic.BaseModel):
    """Represents the API response payload for GET /api/v1/apps."""

    items: list[CatalogApplication]
    total: int
    categories: list[str]
    departments: list[str]
    groups: list[str] = pydantic.Field(default_factory=list)


class SuggestedUser(pydantic.BaseModel):
    """Represents a quick-select Workspace user account for sign-in."""

    email: str
    label: str
    description: str


class AuthConfigResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/auth/config."""

    google_client_id: str = ""
    sso_redirect_enabled: bool = True
    suggested_users: list[SuggestedUser] = pydantic.Field(default_factory=list)


class LoginRequest(pydantic.BaseModel):
    """Represents the request payload for POST /api/v1/auth/login."""

    email: str | None = None
    id_token: str | None = None
    role: str | None = None


class LoginResponse(pydantic.BaseModel):
    """Represents the response payload for POST /api/v1/auth/login."""

    token: str
    user: UserContext


class SyncRunSummary(pydantic.BaseModel):
    """Represents a completed or failed synchronization audit record."""

    id: int
    trigger_source: str
    status: str
    apps_synced: int
    groups_synced: int
    memberships_synced: int
    error_message: str | None = None
    started_at: str | None = None
    completed_at: str | None = None


class SyncStatusResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/sync/status."""

    sync_enabled: bool
    sync_interval_seconds: int
    database_dialect: str
    total_apps: int
    total_groups: int
    total_users: int
    total_memberships: int
    total_skills: int = 0
    pending_skills: int = 0
    last_run: SyncRunSummary | None = None


class SkillIamProposal(pydantic.BaseModel):
    """Represents a pending or active IAM share proposal on a GE skill."""

    proposal_id: str
    principal: str
    role: str = "roles/discoveryengine.agentUser"
    state: str = "ACTIVE"
    create_time: str = ""
    expire_time: str = ""


class SkillSubfile(pydantic.BaseModel):
    """Represents a file bundled in a Gemini Enterprise skill artifact."""

    file_name: str
    mime_type: str = "text/markdown"


class SkillWorkflowItem(pydantic.BaseModel):
    """Represents the 5-stage governance workflow state for a GE skill."""

    workflow_id: str
    skill_id: str
    engine_id: str
    skill_display_name: str
    owner_email: str = ""
    current_stage: str = "SKILL_EVALUATION"
    status: str = "RUNNING"
    eval_score: int = 0
    eval_status: str = "PENDING"
    eval_report: dict[str, Any] = pydantic.Field(default_factory=dict)
    infosec_risk_level: str = "LOW"
    infosec_status: str = "PENDING"
    infosec_report: dict[str, Any] = pydantic.Field(default_factory=dict)
    approval_status: str = "PENDING"
    approved_by: str = ""
    approval_notes: str = ""
    approved_at: str | None = None
    registry_id: str = ""
    shared_in_ge: bool = False
    shared_principals: list[str] = pydantic.Field(default_factory=list)
    started_at: str | None = None
    updated_at: str | None = None
    completed_at: str | None = None


class DiscoveredSkill(pydantic.BaseModel):
    """Represents a Gemini Enterprise skill and its review/sharing status."""

    skill_id: str
    resource_name: str
    engine_id: str
    app_display_name: str
    display_name: str
    description: str = ""
    instruction: str = ""
    gcs_uri: str = ""
    owner_email: str = ""
    state: str = "DISABLED"
    sharing_scope: str = "RESTRICTED"
    sharing_state: str = "PENDING"
    has_active_iam_proposals: bool = False
    review_status: str = "PENDING_REVIEW"
    iam_proposals: list[SkillIamProposal] = pydantic.Field(
        default_factory=list
    )
    shared_principals: list[str] = pydantic.Field(default_factory=list)
    subfiles: list[SkillSubfile] = pydantic.Field(default_factory=list)
    create_time: str = ""
    update_time: str = ""
    last_synced_at: str | None = None
    workflow: SkillWorkflowItem | None = None


class SkillListResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/skills."""

    items: list[DiscoveredSkill]
    total: int
    pending_review_count: int
    approved_count: int
    draft_count: int = 0


class SkillWorkflowStartRequest(pydantic.BaseModel):
    """Request payload for starting a skill governance workflow."""

    skill_id: str


class SkillApprovalRequest(pydantic.BaseModel):
    """Request payload for InfoSec approval or rejection of a skill."""

    approver_email: str = "infosec-admin@mohanrajs.altostrat.com"
    notes: str = ""


class SkillWorkflowListResponse(pydantic.BaseModel):
    """Response payload for GET /api/v1/workflows/skills."""

    items: list[SkillWorkflowItem]
    total: int


class SkillRegistryItem(pydantic.BaseModel):
    """Represents an approved skill published in the Skill Registry."""

    registry_id: str
    skill_id: str
    resource_name: str
    engine_id: str
    app_display_name: str
    display_name: str
    description: str = ""
    instruction: str = ""
    version: str = "1.0.0"
    owner_email: str = ""
    eval_score: int = 0
    infosec_risk_level: str = "LOW"
    approved_by: str = ""
    shared_principals: list[str] = pydantic.Field(default_factory=list)
    published_at: str | None = None


class SkillRegistryListResponse(pydantic.BaseModel):
    """Response payload for GET /api/v1/registry/skills."""

    items: list[SkillRegistryItem]
    total: int


class WorkflowEmailItem(pydantic.BaseModel):
    """Represents a sent or queued InfoSec approval notification email."""

    id: int
    workflow_id: str
    skill_id: str
    recipient_email: str
    subject: str
    body_text: str
    delivery_status: str
    created_at: str | None = None


class WorkflowEmailListResponse(pydantic.BaseModel):
    """Response payload for GET /api/v1/workflows/notifications."""

    items: list[WorkflowEmailItem]
    total: int


class CloudIdentityGroupInfo(pydantic.BaseModel):
    """Represents a synced Cloud Identity group stored in the database."""

    group_email: str
    group_resource_name: str
    display_name: str
    description: str = ""
    member_count: int = 0
    members: list[str] = pydantic.Field(default_factory=list)
    app_engine_ids: list[str] = pydantic.Field(default_factory=list)
    is_member: bool = False
    last_synced_at: str | None = None


class GroupListResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/groups."""

    items: list[CloudIdentityGroupInfo]
    total: int
