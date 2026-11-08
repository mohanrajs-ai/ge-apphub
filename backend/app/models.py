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
    data_store_ids: list[str] = pydantic.Field(default_factory=list)


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
    data_store_ids: list[str] = pydantic.Field(default_factory=list)


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
    """Represents the 6-stage Multi-App AI Skill Hub workflow state."""

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
    templatized_instruction: str = ""
    required_connectors: list[dict[str, str]] = pydantic.Field(
        default_factory=list
    )
    requested_groups: list[str] = pydantic.Field(default_factory=list)
    distribution_scope: str = "SINGLE_APP"
    target_engines: list[str] = pydantic.Field(default_factory=list)
    target_app_evaluations: list[dict[str, Any]] = pydantic.Field(
        default_factory=list
    )
    distributed_apps: list[dict[str, Any]] = pydantic.Field(
        default_factory=list
    )
    sub_skills: list[str] = pydantic.Field(default_factory=list)
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
    sub_skills: list[str] = pydantic.Field(default_factory=list)
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
    target_engines: list[str] | None = None


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
    required_connectors: list[dict[str, str]] = pydantic.Field(
        default_factory=list
    )
    target_engines: list[str] = pydantic.Field(default_factory=list)
    distributed_apps: list[dict[str, Any]] = pydantic.Field(
        default_factory=list
    )
    sub_skills: list[str] = pydantic.Field(default_factory=list)
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


class GeAppProvisionRequest(pydantic.BaseModel):
    """Request payload for Stack 02: Gemini Enterprise App provisioning."""

    gcp_project_id: str = "mohandemo"
    gcp_region: str = "us-central1"
    ge_location: str = "global"
    ge_app_id: str
    ge_app_display_name: str
    ge_company_name: str = "Enterprise Corp"
    ge_solution_type: str = "SOLUTION_TYPE_SEARCH"
    ge_search_tier: str = "SEARCH_TIER_ENTERPRISE"
    ge_enable_llm_addon: bool = True
    ge_industry_vertical: str = "GENERIC"
    ge_data_store_id: str = ""
    ge_data_store_display_name: str = ""
    ge_backing_storage_type: str = "GCS"
    ge_gcs_bucket_name: str = ""
    ge_bq_dataset_id: str = "gemini_enterprise_data"
    ge_identity_provider_type: str = "GSUITE"
    ge_workforce_identity_pool: str = ""
    ge_customer_domain: str = "mohanrajs.altostrat.com"
    ge_app_access_group: str = ""
    ge_app_group_members: str = "admin@mohanrajs.altostrat.com"
    enable_common_connectors: bool = True
    enable_agent_registration: bool = False
    agent_id: str = "universal-skill-orchestrator"
    agent_display_name: str = "Enterprise Skill Orchestrator"
    agent_description: str = (
        "Executes governed Parent Skills and Sub-Skills from the AI Skill Hub."
    )
    agent_reasoning_engine: str = ""
    tf_state_bucket: str = ""
    execution_mode: str = "PLAN_AND_WAIT"


class IdentityProvisionRequest(pydantic.BaseModel):
    """Request payload for Stack 01: Entra ID / Cloud Identity WIF & SAML."""

    gcp_project_id: str = "mohandemo"
    gcp_region: str = "us-central1"
    gcp_org_id: str = "123456789012"
    ge_location: str = "global"
    cloud_identity_customer_id: str = "customers/C01234567"
    primary_customer_domain: str = "mohanrajs.altostrat.com"
    shared_identity_domain: str = "mohanrajs.altostrat.com"
    m365_secret_id: str = "m365-connector-credentials"
    m365_tenant_id: str = ""
    m365_client_id: str = ""
    m365_client_secret: str = ""
    entra_group_filter: str = "startswith(mailNickname,'ge-')"
    entra_to_app_group_mappings: str = ""
    enable_cloud_identity_saml_sso: bool = True
    saml_sso_profile_display_name: str = "Microsoft Entra ID SSO"
    enable_workforce_pool_oidc: bool = False
    workforce_pool_id: str = "entra-id-shared-pool"
    workforce_provider_id: str = "entra-id-oidc-provider"
    tf_state_bucket: str = ""
    execution_mode: str = "PLAN_AND_WAIT"


class M365ConnectorProvisionRequest(pydantic.BaseModel):
    """Request payload for Stack 03: Microsoft 365 Data Connectors."""

    gcp_project_id: str = "mohandemo"
    gcp_region: str = "us-central1"
    ge_location: str = "global"
    m365_collection_prefix: str = "m365"
    ge_app_id: str = ""
    m365_secret_id: str = "m365-connector-credentials"
    m365_tenant_id: str = ""
    m365_client_id: str = ""
    m365_client_secret: str = ""
    m365_connector_mode: str = "FEDERATED"
    enable_m365_actions: bool = True
    enable_sharepoint_connector: bool = True
    m365_sharepoint_instance_uri: str = "https://contoso.sharepoint.com"
    enable_onedrive_connector: bool = True
    m365_onedrive_instance_uri: str = "https://contoso-my.sharepoint.com"
    enable_outlook_connector: bool = True
    enable_teams_connector: bool = True
    tf_state_bucket: str = ""
    execution_mode: str = "PLAN_AND_WAIT"


class ProvisioningApprovalRequest(pydantic.BaseModel):
    """Request payload for approving or rejecting a planned Terraform job."""

    notes: str = ""


class ProvisioningJobItem(pydantic.BaseModel):
    """Represents a persisted Terraform provisioning job and its plan/logs."""

    job_id: str
    stack_type: str
    title: str
    workspace_key: str
    state_backend_type: str
    state_bucket: str = ""
    state_prefix: str = ""
    execution_mode: str
    status: str
    initiated_by: str
    approved_by: str = ""
    sanitized_config: dict[str, Any] = pydantic.Field(default_factory=dict)
    plan_summary: str = ""
    log_lines: list[str] = pydantic.Field(default_factory=list)
    outputs: dict[str, Any] = pydantic.Field(default_factory=dict)
    error_message: str | None = None
    created_at: str | None = None
    updated_at: str | None = None
    completed_at: str | None = None


class ProvisioningJobListResponse(pydantic.BaseModel):
    """Response payload for GET /api/v1/admin/provisioning/jobs."""

    items: list[ProvisioningJobItem]
    total: int
    active_workspace_locks: list[str] = pydantic.Field(default_factory=list)


class SubSkillStepTrace(pydantic.BaseModel):
    """Represents a single Sub-Skill execution step via GE :streamAssist."""

    step_index: int
    sub_skill_name: str
    sub_skill_display_name: str
    sub_skill_input: str
    status: str = "COMPLETED"
    stream_assist_endpoint: str
    identity_mode: str = "USER_OAUTH_PASSTHROUGH"
    output_summary: str
    connectors_invoked: list[str] = pydantic.Field(default_factory=list)
    latency_ms: int = 120


class SkillOrchestrateRequest(pydantic.BaseModel):
    """Request payload for invoking the Universal Skill Orchestrator Agent."""

    skill_id: str
    engine_id: str = ""
    user_prompt: str = (
        "Triage the P1 customer escalation email from Contoso Corp and verify "
        "applicable SLA credit policy."
    )
    forwarded_oauth_token: str = ""


class SkillOrchestrateResponse(pydantic.BaseModel):
    """Response payload from the Universal Skill & Sub-Skill Orchestrator."""

    orchestration_id: str
    agent_name: str = "universal_skill_orchestrator"
    skill_id: str
    skill_display_name: str
    engine_id: str
    calling_user_email: str
    identity_passthrough_mode: str
    stream_assist_endpoint: str
    is_composite_skill: bool = False
    sub_skills_loaded: list[str] = pydantic.Field(default_factory=list)
    sub_skill_traces: list[SubSkillStepTrace] = pydantic.Field(
        default_factory=list
    )
    final_response: str
    total_tokens_saved: int = 0
    executed_at: str


class SkillCatalogSeedResponse(pydantic.BaseModel):
    """Response payload for seeding atomic sub-skills and composite skills."""

    seeded_skills: list[str] = pydantic.Field(default_factory=list)
    total_seeded: int = 0


class GePinnedAgentPublishRequest(pydantic.BaseModel):
    """Request payload for publishing Universal Orchestrator as Pinned Agent."""

    engine_id: str = "service-desk-app-01"
    display_name: str = "Enterprise Skill Orchestrator"
    description: str = (
        "Executes governed Parent Skills and Sub-Skills from the AI Skill Hub "
        "using your Gemini Enterprise identity."
    )
    authorization_id: str = "ge-user-oauth-passthrough"
    registration_mode: str = "adk"
    default_pinned: bool = True


class GePinnedAgentItem(pydantic.BaseModel):
    """Represents a Pinned Assistant registered on a Gemini Enterprise App."""

    agent_resource_name: str
    engine_id: str
    app_display_name: str
    agent_id: str = "universal-skill-orchestrator"
    display_name: str
    description: str
    registration_mode: str = "adk"
    default_pinned: bool = True
    authorization_resource: str
    reasoning_engine: str
    agents_cli_command: str
    starter_prompts: list[str] = pydantic.Field(default_factory=list)
    custom_placeholder_text: str = (
        "Ask the Enterprise Skill Orchestrator to run a governed skill or "
        "multi-step workflow..."
    )
    status: str = "PINNED_ACTIVE"
    updated_at: str


class GePinnedAgentListResponse(pydantic.BaseModel):
    """Response payload for GET /api/v1/admin/ge-agents/registry."""

    items: list[GePinnedAgentItem]
    total: int


