/**
 * Shared TypeScript interfaces for the Gemini Enterprise AppHub catalog.
 */

export interface UserContext {
  email: string;
  user_id: string;
  roles: string[];
  groups?: string[];
  auth_source: string;
}

export interface SuggestedUser {
  email: string;
  label: string;
  description: string;
}

export interface AuthConfigResponse {
  google_client_id: string;
  sso_redirect_enabled?: boolean;
  suggested_users: SuggestedUser[];
}

export interface LoginResponse {
  token: string;
  user: UserContext;
}

export interface CatalogApplication {
  engine_id: string;
  display_name: string;
  description: string;
  category: string;
  department: string;
  tags: string[];
  icon_name: string;
  launch_url: string;
  location: string;
  solution_type: string;
  allowed_roles: string[];
  featured: boolean;
}

export interface CatalogResponse {
  items: CatalogApplication[];
  total: number;
  categories: string[];
  departments: string[];
  groups?: string[];
}

export interface AppsQueryParams {
  devRole?: string;
  authToken?: string;
  q?: string;
  category?: string;
  department?: string;
  tag?: string;
  group?: string;
}

export interface SyncRunSummary {
  id: number;
  trigger_source: string;
  status: string;
  apps_synced: number;
  groups_synced: number;
  memberships_synced: number;
  error_message?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
}

export type PortalSection = 'apps' | 'skills' | 'agents';

export interface SyncStatusResponse {
  sync_enabled: boolean;
  sync_interval_seconds: number;
  database_dialect: string;
  total_apps: number;
  total_groups: number;
  total_users: number;
  total_memberships: number;
  total_skills?: number;
  pending_skills?: number;
  last_run?: SyncRunSummary | null;
}

export interface SkillIamProposal {
  proposal_id: string;
  principal: string;
  role: string;
  state: string;
  create_time: string;
  expire_time: string;
}

export interface SkillSubfile {
  file_name: string;
  mime_type: string;
}

export interface SkillWorkflowCheck {
  check: string;
  passed: boolean;
  detail: string;
}

export interface SkillTokenOptimization {
  discovery_tokens: number;
  instruction_tokens: number;
  total_tokens: number;
  optimized_instruction_tokens: number;
  optimized_total_tokens: number;
  tokens_saved: number;
  reduction_pct: number;
  duplicate_uri_count: number;
  efficiency_grade: string;
  recommendations?: string[];
}

export interface SkillWorkflowItem {
  workflow_id: string;
  skill_id: string;
  engine_id: string;
  skill_display_name: string;
  owner_email: string;
  current_stage:
    | 'SKILL_EVALUATION'
    | 'INFOSEC_SCAN'
    | 'AWAITING_INFOSEC_APPROVAL'
    | 'PUBLISH_REGISTRY'
    | 'SHARE_TO_APP'
    | 'COMPLETED'
    | 'REJECTED'
    | 'FAILED'
    | string;
  status: string;
  eval_score: number;
  eval_status: string;
  eval_report?: {
    agent_name?: string;
    score?: number;
    passed?: boolean;
    verdict?: string;
    summary?: string;
    checks?: SkillWorkflowCheck[];
    token_optimization?: SkillTokenOptimization;
  };
  infosec_risk_level: string;
  infosec_status: string;
  infosec_report?: {
    agent_name?: string;
    risk_level?: string;
    passed?: boolean;
    verdict?: string;
    summary?: string;
    findings?: string[];
    checks?: SkillWorkflowCheck[];
  };
  approval_status: string;
  approved_by: string;
  approval_notes: string;
  approved_at?: string | null;
  registry_id: string;
  shared_in_ge: boolean;
  shared_principals: string[];
  started_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
}

export interface DiscoveredSkill {
  skill_id: string;
  resource_name: string;
  engine_id: string;
  app_display_name: string;
  display_name: string;
  description: string;
  instruction: string;
  gcs_uri: string;
  owner_email: string;
  state: string;
  sharing_scope: string;
  sharing_state: string;
  has_active_iam_proposals: boolean;
  review_status: 'PENDING_REVIEW' | 'APPROVED' | 'DRAFT' | string;
  iam_proposals: SkillIamProposal[];
  shared_principals: string[];
  subfiles: SkillSubfile[];
  create_time: string;
  update_time: string;
  last_synced_at?: string | null;
  workflow?: SkillWorkflowItem | null;
}

export interface SkillRegistryItem {
  registry_id: string;
  skill_id: string;
  resource_name: string;
  engine_id: string;
  app_display_name: string;
  display_name: string;
  description: string;
  instruction: string;
  version: string;
  owner_email: string;
  eval_score: number;
  infosec_risk_level: string;
  approved_by: string;
  shared_principals: string[];
  published_at?: string | null;
}

export interface SkillRegistryListResponse {
  items: SkillRegistryItem[];
  total: number;
}

export interface WorkflowEmailItem {
  id: number;
  workflow_id: string;
  skill_id: string;
  recipient_email: string;
  subject: string;
  body_text: string;
  delivery_status: string;
  created_at?: string | null;
}

export interface WorkflowEmailListResponse {
  items: WorkflowEmailItem[];
  total: number;
}

export interface SkillListResponse {
  items: DiscoveredSkill[];
  total: number;
  pending_review_count: number;
  approved_count: number;
  draft_count: number;
}

export interface SkillsQueryParams {
  devRole?: string;
  authToken?: string;
  reviewStatus?: string;
  engineId?: string;
  q?: string;
}
