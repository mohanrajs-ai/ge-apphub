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

export interface SyncStatusResponse {
  sync_enabled: boolean;
  sync_interval_seconds: number;
  database_dialect: string;
  total_apps: number;
  total_groups: number;
  total_users: number;
  total_memberships: number;
  last_run?: SyncRunSummary | null;
}
