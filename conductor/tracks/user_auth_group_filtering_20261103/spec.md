# Specification: User Authentication & Group-Based Catalog Filtering (`user_auth_group_filtering_20261103`)

## 1. Overview
This track adds end-to-end user authentication, session management, and Cloud Identity group-based catalog filtering to **Tech-M Gemini AI Hub (`ge-apphub`)**. Users sign in via a dedicated Sign-In screen (supporting Google Sign-In OAuth 2.0 ID token verification and Workspace account login/switching such as `mohanraj@mohanrajs.altostrat.com` and `admin@mohanrajs.altostrat.com`). Upon sign-in, the backend resolves the user's Cloud Identity group memberships (`groups:lookup` and `memberships:checkTransitiveMembership`), evaluates each Gemini Enterprise engine's IAM policy (`engines:getIamPolicy`), and surfaces only the applications the user's groups can access, along with interactive group filter chips and group badges in the UI.

## 2. Functional Requirements

### 2.1 Backend Authentication & Group Access API (`/backend`)
- **Authentication Endpoints (`/api/v1/auth`):**
  - `GET /api/v1/auth/config`: Returns client auth configuration (`google_client_id` if configured via `GOOGLE_CLIENT_ID`, and suggested Workspace accounts for quick testing).
  - `POST /api/v1/auth/login`: Accepts either a Google OAuth `id_token` (verified via `google.oauth2.id_token.verify_oauth2_token`) or a Workspace `email` login request, validates the identity, resolves the user's Cloud Identity groups across discovered engines, and returns a signed session token + `UserContext` (`email`, `user_id`, `roles`, `groups`, `auth_source`).
  - `POST /api/v1/auth/logout`: Invalidates/clears the active session.
- **Identity & Cloud Identity Group Resolution (`auth.py`, `discovery.py`, `catalog.py`):**
  - Resolve user identity from Google Cloud IAP (`X-Goog-Authenticated-User-Email`), `Authorization: Bearer <token>` session header, or dev override headers (`X-Dev-User-Email`, `X-Dev-User-Role`).
  - Populate `UserContext.groups` on `/api/v1/me` and `/api/v1/auth/login` with the Cloud Identity groups the user belongs to.
  - Filter `GET /api/v1/apps` strictly by the user's Cloud Identity group memberships against each engine's `getIamPolicy` bindings (`group:<email>`), and support an optional `group` filter parameter.

### 2.2 Frontend Sign-In Gate & Group Filter UI (`/frontend`)
- **Dedicated Sign-In Screen (`LoginScreen.tsx`):**
  - Displayed before accessing the catalog when unauthenticated.
  - Supports signing in with a Workspace email address, Google Sign-In (when `google_client_id` is configured), and one-click Workspace user cards (`mohanraj@mohanrajs.altostrat.com` and `admin@mohanrajs.altostrat.com`) to immediately test group-scoped visibility.
- **Header Session & Group Summary (`Header.tsx`):**
  - Displays the signed-in user's email, count/list of active Cloud Identity groups, and a **Sign Out / Switch User** button.
- **Interactive Group Filter & Card Group Badges (`SearchFilterBar.tsx` & `AppCard.tsx`):**
  - Adds a **My Access Groups** filter bar allowing the user to filter visible applications by specific Cloud Identity group (e.g., `hr-app-01-users@mohanrajs.altostrat.com`, `ops-app-01-users@mohanrajs.altostrat.com`).
  - Displays the authorized Cloud Identity group badge on each application card.

## 3. Non-Functional Requirements
- **Test-Driven Development:** >80% test coverage across backend (`pytest`) and frontend (`vitest`).
- **Performance:** In-memory caching of Discovery Engine IAM policies and Cloud Identity group lookups for fast (<100ms) catalog filtering after initial warmup.

## 4. Acceptance Criteria
1. Unauthenticated users see the Sign-In screen (`LoginScreen`) before accessing the catalog.
2. Signing in as `mohanraj@mohanrajs.altostrat.com` resolves `["hr-app-01-users@mohanrajs.altostrat.com", "ops-app-01-users@mohanrajs.altostrat.com"]` and shows only **Gemini HR App** and **Gemini Ops App**.
3. Signing in as `admin@mohanrajs.altostrat.com` resolves their 6 Cloud Identity groups and shows only those **6 applications** (excluding **Gemini HR App**).
4. Users can filter visible apps by Cloud Identity group chip and click **Sign Out** to switch accounts.
5. Backend (`pytest`) and frontend (`vitest`) test suites pass with >80% coverage.
