# Implementation Plan: Gemini Enterprise AppHub MVP (`mvp_ge_apphub_20261028`)

## Phase 1: Monorepo Scaffolding & Backend Foundation [checkpoint: 2c2f58f]
- [x] Task: Initialize Python backend project structure and FastAPI health endpoint d0f8037
  - [x] Create `/backend` directory, `pyproject.toml` / `requirements.txt`, and environment configuration (`config.py`) supporting `GCP_PROJECT_ID`, `GCP_LOCATION`, `FIRESTORE_COLLECTION`, and `USE_MOCK_DATA`
  - [x] Write failing unit tests (`backend/tests/test_health.py`) for `GET /api/v1/health` and configuration loading (Red Phase)
  - [x] Implement FastAPI application factory (`backend/app/main.py`) and `/api/v1/health` endpoint to pass tests (Green Phase)
  - [x] Verify `pytest --cov=app` passes with >80% coverage and clean `ruff` linting
- [x] Task: Implement User Identity & Role Resolution Middleware/Dependency 2c2f58f
  - [x] Write failing unit tests (`backend/tests/test_auth.py`) for extracting user email and roles from Google Cloud IAP headers (`X-Goog-Authenticated-User-Email`) and local dev override headers (`X-Dev-User-Email`, `X-Dev-User-Role`) (Red Phase)
  - [x] Implement authentication dependency (`backend/app/auth.py`), Pydantic user models (`backend/app/models.py`), and `GET /api/v1/me` endpoint (Green Phase)
  - [x] Verify test suite passes with >80% coverage
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) 2c2f58f

## Phase 2: Discovery Engine SDK & Firestore Metadata Enrichment Pipeline [checkpoint: 0870d36]
- [x] Task: Implement Discovery Engine client service and mock fallback provider f1ba356
  - [x] Write failing unit tests (`backend/tests/test_discovery_service.py`) mocking `google-cloud-discoveryengine` (`EngineServiceClient.list_engines`) and testing mock fallback mode (Red Phase)
  - [x] Implement `DiscoveryEngineService` (`backend/app/services/discovery.py`) to list GE engines and map them to normalized internal models, including curated mock engines when `USE_MOCK_DATA=true` (Green Phase)
  - [x] Verify test suite passes with >80% coverage
- [x] Task: Implement Firestore metadata enrichment service and catalog merger 0870d36
  - [x] Write failing unit tests (`backend/tests/test_catalog_service.py`) verifying Firestore document retrieval (`google-cloud-firestore`), metadata merging (categories, departments, tags, descriptions, launch URLs, and `allowed_roles`), role-based visibility filtering, and search/query filtering (Red Phase)
  - [x] Implement `FirestoreMetadataService` (`backend/app/services/firestore.py`) and `CatalogService` (`backend/app/services/catalog.py`) to merge live/mock engines with Firestore metadata and enforce role-based visibility (Green Phase)
  - [x] Write failing API integration tests (`backend/tests/test_apps_api.py`) for `GET /api/v1/apps` with search (`q`), `category`, `department`, `tag`, and role filtering (Red Phase)
  - [x] Implement `GET /api/v1/apps` router (`backend/app/routers/apps.py`) and wire into FastAPI app (Green Phase)
  - [x] Verify backend test suite passes with >80% coverage and zero lint issues
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) 0870d36

## Phase 3: React + TypeScript Frontend Scaffolding & Theme/Identity Shell [checkpoint: d7cc948]
- [x] Task: Scaffold `/frontend` with React 18, Vite, TypeScript, Tailwind CSS, and Vitest d7cc948
  - [x] Initialize `/frontend` project with Vite (`react-ts`), Tailwind CSS configured with Material 3 / Gemini color tokens, Lucide icons, and Vitest + React Testing Library setup
  - [x] Write failing component tests (`frontend/src/__tests__/Header.test.tsx`) for the AppHub Header, branding, Light/Dark theme toggle, and local dev role-switcher control (Red Phase)
  - [x] Implement `ThemeContext`, `Header` component, and API client service (`frontend/src/api/client.ts`) fetching `/api/v1/me` and `/api/v1/apps` (Green Phase)
  - [x] Verify `CI=true npm test` passes with >80% coverage
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) d7cc948

## Phase 4: Searchable & Filterable Application Catalog UI
- [x] Task: Implement Search Bar, Category/Department Filter Chips, and Application Card Grid 50585d1
  - [x] Write failing unit/integration tests (`frontend/src/__tests__/Catalog.test.tsx`) covering real-time search input, category and department chip filtering, clear-filters button, card rendering (icon, badges, outcome summary, tags, Launch App link), loading skeletons, and empty/error states (Red Phase)
  - [x] Implement `SearchFilterBar`, `AppCard`, `CatalogGrid`, and main `App` view (Green Phase)
  - [x] Refactor UI styling for Material 3 / Cloud Console polish, responsive grid layout, and WCAG AA accessibility
  - [x] Verify frontend test coverage (>80%) and TypeScript build (`npm run build`)
- [x] Task: Wire Production Static Asset Serving & Containerization 6dd61db
  - [x] Write failing backend test verifying FastAPI static SPA fallback mounting when `frontend/dist` is present (Red Phase)
  - [x] Implement SPA static mounting in `backend/app/main.py` and add root `Dockerfile` / startup scripts for unified local and Cloud Run execution (Green Phase)
  - [x] Run full backend (`pytest --cov=app`) and frontend (`CI=true npm test -- --coverage`) suites
- [~] Task: Phase Verification & Checkpoint (Refer to workflow.md)
