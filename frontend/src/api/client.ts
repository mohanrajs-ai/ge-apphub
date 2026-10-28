/**
 * REST API client for communicating with the Gemini Enterprise AppHub backend.
 */

import {
  AppsQueryParams,
  CatalogResponse,
  UserContext,
} from '../types/catalog';

function buildHeaders(devRole?: string): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  if (devRole) {
    headers['X-Dev-User-Role'] = devRole;
  }
  return headers;
}

/**
 * Fetches the resolved user identity and roles from /api/v1/me.
 */
export async function fetchCurrentUser(devRole?: string): Promise<UserContext> {
  const response = await fetch('/api/v1/me', {
    headers: buildHeaders(devRole),
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch user profile: HTTP ${response.status}`);
  }
  const data: UserContext = await response.json();
  return data;
}

/**
 * Fetches the role-filtered application catalog from /api/v1/apps.
 */
export async function fetchApps(
  params: AppsQueryParams = {},
): Promise<CatalogResponse> {
  const searchParams = new URLSearchParams();
  if (params.q) {
    searchParams.set('q', params.q);
  }
  if (params.category) {
    searchParams.set('category', params.category);
  }
  if (params.department) {
    searchParams.set('department', params.department);
  }
  if (params.tag) {
    searchParams.set('tag', params.tag);
  }
  const queryString = searchParams.toString();
  const url = queryString ? `/api/v1/apps?${queryString}` : '/api/v1/apps';

  const response = await fetch(url, {
    headers: buildHeaders(params.devRole),
  });
  if (!response.ok) {
    throw new Error(
      `Failed to fetch application catalog: HTTP ${response.status}`,
    );
  }
  const data: CatalogResponse = await response.json();
  return data;
}
