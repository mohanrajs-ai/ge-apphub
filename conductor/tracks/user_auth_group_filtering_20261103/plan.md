# Implementation Plan: User Authentication & Group-Based Catalog Filtering (`user_auth_group_filtering_20261103`)

## Phase 1: Backend Authentication Session API & Cloud Identity Group Resolution
- [ ] Task: Implement `/api/v1/auth` login, logout, config endpoints and signed session token verification
  - [ ] Write failing unit and integration tests (`backend/tests/test_auth.py`) for `GET /api/v1/auth/config`, `POST /api/v1/auth/login` (Google ID token and Workspace email sign-in), `POST /api/v1/auth/logout`, Bearer token resolution in `GET /api/v1/me`, and Cloud Identity `groups` enrichment (Red Phase)
  - [ ] Implement signed token generation/verification in `backend/app/auth.py` and `/api/v1/auth` router (`backend/app/routers/auth.py`), resolving `UserContext.groups` via `DiscoveryEngineService.resolve_user_groups` (Green Phase)
  - [ ] Support `group` query filtering on `GET /api/v1/apps` (`backend/app/routers/apps.py` & `backend/app/services/catalog.py`) and verify `pytest --cov=app` passes with >80% coverage
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Frontend Sign-In Gate, Group Filter Chips & Account Switching UI
- [ ] Task: Implement `LoginScreen`, Auth Session State, Group Filter Chips, and Card Group Badges
  - [ ] Write failing frontend component and integration tests (`frontend/src/__tests__/Header.test.tsx` and `frontend/src/__tests__/Catalog.test.tsx`) covering the `LoginScreen` sign-in flow, user session persistence, Sign Out / Switch User action, active Cloud Identity group filter chips in `SearchFilterBar`, and group badges on `AppCard` (Red Phase)
  - [ ] Implement `LoginScreen.tsx`, update `client.ts` with `loginWithUser`, `logoutUser`, and Bearer token headers, and update `Header.tsx`, `SearchFilterBar.tsx`, `AppCard.tsx`, and `App.tsx` (Green Phase)
  - [ ] Rebuild production frontend bundle (`npm run build`) and verify `CI=true npm test -- --coverage` passes with >80% coverage
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
