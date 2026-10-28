# Specification: Gemini Enterprise AppHub MVP (`mvp_ge_apphub_20261028`)

## 1. Overview
This track delivers the Minimum Viable Product (MVP) for **Gemini Enterprise AppHub (`ge-apphub`)**—a centralized enterprise marketplace and discovery portal for Gemini Enterprise (GE) applications. The MVP establishes the monorepo architecture (`/backend` in Python + FastAPI and `/frontend` in React + TypeScript + Tailwind CSS), integrates with Google Cloud Discovery Engine and Cloud Firestore to surface enriched application metadata, enforces role-aware catalog visibility via Google Cloud IAP / OAuth headers (with a local development role switcher), and provides a zero-friction, searchable, and filterable catalog UI.

## 2. Functional Requirements

### 2.1 Backend API (`/backend` — Python 3.11+ & FastAPI)
- **Discovery Engine Integration (`google-cloud-discoveryengine`):**
  - Query Gemini Enterprise / Discovery Engine applications (`EngineServiceClient.list_engines`) across configured GCP project(s) and location(s) (e.g., `global`, `us`, `eu`).
  - Extract core engine metadata: `engine_id`, `display_name`, `solution_type`, `industry_vertical`, `app_type`, and default console/web launch URI.
- **Firestore Metadata Enrichment (`google-cloud-firestore`):**
  - Fetch enrichment documents from a configurable Firestore collection (default: `ge_app_catalog`) keyed by `engine_id`.
  - Merge enrichment fields onto discovered engines: `description` (outcome-oriented summary), `category` (e.g., *Productivity*, *Data & Analytics*, *Customer Support*, *Engineering*), `department`, `tags` (list of strings), `icon_url` / icon identifier, `launch_url` override, and `allowed_roles` / visibility rules.
- **Local Mock / Fallback Mode:**
  - When `USE_MOCK_DATA=true` or when GCP credentials are not configured in local development, serve a realistic curated dataset of Gemini Enterprise applications and Firestore enrichments so development and automated testing run deterministically without live cloud dependencies.
- **Identity & Role-Based Visibility:**
  - Inspect Google Cloud IAP headers (`X-Goog-Authenticated-User-Email`, `X-Goog-Authenticated-User-Id`) or Bearer tokens in production.
  - In local development mode, support a `X-Dev-User-Role` / `X-Dev-User-Email` header or query override so developers and testers can preview role-based catalog filtering.
  - Filter the returned application list so users only see applications matching their assigned role(s) or marked as organization-wide (`public` / `*`).
- **REST Endpoints:**
  - `GET /api/v1/health`: Health and readiness check including configuration mode (`live` vs `mock`).
  - `GET /api/v1/me`: Returns the current resolved user identity and active roles.
  - `GET /api/v1/apps`: Returns the role-filtered list of Gemini Enterprise applications, supporting server-side or client-assisted filtering by `q` (search query), `category`, `department`, and `tag`.
- **Static Frontend Serving:**
  - When the compiled frontend (`frontend/dist`) exists, mount and serve static assets and SPA fallback routing from FastAPI for single-container Cloud Run deployment.

### 2.2 Frontend Portal (`/frontend` — React 18, Vite, TypeScript & Tailwind CSS)
- **Header & Navigation Bar:**
  - Gemini Enterprise AppHub branding with subtle Gemini AI gradient accents.
  - Active user badge showing email/role (with a role-switcher dropdown when running in local development/mock mode).
  - Light / Dark theme toggle persisted in `localStorage` and respecting system preferences.
- **Instant Search & Multi-Faceted Filtering:**
  - Prominent search input filtering applications in real time across title, description, category, department, and tags.
  - Interactive filter chips for **Category** and **Department**, plus active filter count and a one-click *Clear Filters* action.
- **Application Catalog Grid & Embedded Iframe Viewer:**
  - Responsive Material 3 / Cloud Console-inspired card grid.
  - Each card displays: Application Icon, Display Name, Category & Department badges, concise 1–2 sentence outcome-oriented description, capability tags, and a prominent **Launch App** button.
  - Clicking **Launch App** renders the target Gemini Enterprise application URL (such as `https://auth.cloud.google/signin/locations/global/workforcePools/mohan-entra-id-oidc-pool/providers/entra-id-oidc-pool-provider?continueUrl=https%3A%2F%2Fvertexaisearch.cloud.google%2Fhome%2Fcid%2Fa8265c54-515b-413b-aaa2-828f0d65d29e&hl=en_US`) inside an embedded `<iframe>` workspace view rather than redirecting the browser tab.
- **Empty, Loading & Error States:**
  - Skeleton loading cards while fetching data.
  - Helpful empty state when search/filter combinations match no applications, with a quick reset button.
  - Actionable error banner with retry button if the backend API is unreachable.

## 3. Non-Functional Requirements
- **Test-Driven Development & Coverage:** >80% unit and integration test coverage across both `/backend` (`pytest`) and `/frontend` (`vitest` + React Testing Library).
- **Performance:** Instant client-side search/filter responsiveness (<50ms UI update) and clean async backend response handling.
- **Code Quality & Type Safety:** Strict TypeScript typing (`tsc --noEmit`) and clean Python linting/formatting (`ruff`).
- **Accessibility:** Semantic HTML landmarks, keyboard-navigable search/filter controls, and high-contrast light/dark color tokens.

## 4. Acceptance Criteria
1. Backend API serves `GET /api/v1/health`, `GET /api/v1/me`, and `GET /api/v1/apps` with full Pydantic validation and >80% `pytest` coverage.
2. Discovery Engine client and Firestore enrichment service merge engine records with custom metadata and gracefully support mock mode when `USE_MOCK_DATA=true`.
3. Role-based visibility filtering hides restricted GE apps from unauthorized roles and surfaces them when an authorized role is active.
4. Frontend renders the searchable, filterable App Catalog Grid with light/dark mode support, responsive cards, one-click app launch links, and >80% `vitest` coverage.

## 5. Out of Scope (Deferred to Future Tracks)
- In-app Admin UI for editing Firestore enrichment metadata directly from the browser.
- Custom native chat client implementation (MVP embeds the target Gemini Enterprise web application inside an `<iframe>` workspace).
- End-user ratings, reviews, and bookmark persistence in Firestore.
