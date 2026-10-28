/**
 * Shared TypeScript interfaces for the Gemini Enterprise AppHub catalog.
 */

export interface UserContext {
  email: string;
  user_id: string;
  roles: string[];
  auth_source: string;
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
}

export interface AppsQueryParams {
  devRole?: string;
  q?: string;
  category?: string;
  department?: string;
  tag?: string;
}
