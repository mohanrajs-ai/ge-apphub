/**
 * REST API client for communicating with the Gemini Enterprise AppHub backend.
 */

import {
  AppsQueryParams,
  AuthConfigResponse,
  CatalogResponse,
  LoginResponse,
  SkillListResponse,
  SkillsQueryParams,
  SyncRunSummary,
  SyncStatusResponse,
  UserContext,
} from '../types/catalog';

function buildHeaders(
  devRole?: string,
  authToken?: string,
): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  if (devRole) {
    headers['X-Dev-User-Role'] = devRole;
  }
  if (authToken) {
    headers.Authorization = `Bearer ${authToken}`;
  }
  return headers;
}

/**
 * Fetches authentication configuration and suggested Workspace accounts.
 */
export async function fetchAuthConfig(): Promise<AuthConfigResponse> {
  const response = await fetch('/api/v1/auth/config', {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch auth config: HTTP ${response.status}`);
  }
  const data: AuthConfigResponse = await response.json();
  return data;
}

/**
 * Builds the backend Google Cloud Identity / Microsoft 365 SAML SSO login URL.
 */
export function buildGoogleSsoLoginUrl(email?: string): string {
  const params = new URLSearchParams();
  if (email && email.trim()) {
    params.set('email', email.trim().toLowerCase());
  }
  if (typeof window !== 'undefined' && window.location?.origin) {
    params.set('redirect_origin', window.location.origin);
  }
  const query = params.toString();
  return query
    ? `/api/v1/auth/google/login?${query}`
    : '/api/v1/auth/google/login';
}

/**
 * Signs in a user with their Google Workspace email address.
 */
export async function loginWithEmail(email: string): Promise<LoginResponse> {
  const response = await fetch('/api/v1/auth/login', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email }),
  });
  if (!response.ok) {
    throw new Error(`Authentication failed: HTTP ${response.status}`);
  }
  const data: LoginResponse = await response.json();
  return data;
}

/**
 * Logs out the current user session.
 */
export async function logoutUser(): Promise<void> {
  await fetch('/api/v1/auth/logout', {
    method: 'POST',
    headers: { Accept: 'application/json' },
  });
}

/**
 * Fetches the resolved user identity and roles from /api/v1/me.
 */
export async function fetchCurrentUser(
  devRole?: string,
  authToken?: string,
): Promise<UserContext> {
  const response = await fetch('/api/v1/me', {
    headers: buildHeaders(devRole, authToken),
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch user profile: HTTP ${response.status}`);
  }
  const data: UserContext = await response.json();
  return data;
}

/**
 * Fetches the role- and group-filtered application catalog from /api/v1/apps.
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
  if (params.group) {
    searchParams.set('group', params.group);
  }
  const queryString = searchParams.toString();
  const url = queryString ? `/api/v1/apps?${queryString}` : '/api/v1/apps';

  const response = await fetch(url, {
    headers: buildHeaders(params.devRole, params.authToken),
  });
  if (!response.ok) {
    throw new Error(
      `Failed to fetch application catalog: HTTP ${response.status}`,
    );
  }
  const data: CatalogResponse = await response.json();
  return data;
}

/**
 * Fetches current database sync status and entity counts from /api/v1/sync/status.
 */
export async function fetchSyncStatus(): Promise<SyncStatusResponse> {
  const response = await fetch('/api/v1/sync/status', {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch sync status: HTTP ${response.status}`);
  }
  const data: SyncStatusResponse = await response.json();
  return data;
}

/**
 * Triggers an immediate synchronization of GE applications and Cloud Identity groups.
 */
export async function triggerSync(): Promise<SyncRunSummary> {
  const response = await fetch('/api/v1/sync', {
    method: 'POST',
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Failed to trigger sync: HTTP ${response.status}`);
  }
  const data: SyncRunSummary = await response.json();
  return data;
}

/**
 * Fetches synced Gemini Enterprise skills and share approval status from /api/v1/skills.
 */
export async function fetchSkills(
  params: SkillsQueryParams = {},
): Promise<SkillListResponse> {
  const searchParams = new URLSearchParams();
  if (params.reviewStatus && params.reviewStatus !== 'ALL') {
    searchParams.set('review_status', params.reviewStatus);
  }
  if (params.engineId) {
    searchParams.set('engine_id', params.engineId);
  }
  if (params.q) {
    searchParams.set('q', params.q);
  }
  const queryString = searchParams.toString();
  const url = queryString ? `/api/v1/skills?${queryString}` : '/api/v1/skills';

  const response = await fetch(url, {
    headers: buildHeaders(params.devRole, params.authToken),
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch skills: HTTP ${response.status}`);
  }
  const data: SkillListResponse = await response.json();
  return data;
}
