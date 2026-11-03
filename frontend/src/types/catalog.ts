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
