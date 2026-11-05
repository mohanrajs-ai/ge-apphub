# Implementation Plan: PostgreSQL Persistence, Cloud Identity Auth & Scheduled Sync (`postgres_cloud_identity_sync_20261105`)

## Phase 1: Local PostgreSQL Provisioning & SQLAlchemy ORM Schema [checkpoint: b74ef07]
- [x] Task: Update `conductor/tech-stack.md`, provision local PostgreSQL database, and implement SQLAlchemy ORM models `b74ef07`
  - [x] Document PostgreSQL, SQLAlchemy 2.0 (`psycopg`), and scheduled sync worker in `conductor/tech-stack.md` and create `docker-compose.yml` for local PostgreSQL
  - [x] Install and start local PostgreSQL service (`postgresql@16` via Homebrew), create the `geapphub` database, and install Python dependencies (`sqlalchemy`, `psycopg[binary]`)
  - [x] Write failing unit tests (`backend/tests/test_database.py`) for database session management and ORM models (`UserRecord`, `CloudIdentityGroupRecord`, `UserGroupMembershipRecord`, `GEApplicationRecord`, `AppGroupBindingRecord`, `SyncRunRecord`)
  - [x] Implement `backend/app/database.py` and `backend/app/db_models.py` with automatic schema initialization and update `backend/app/config.py` with PostgreSQL and sync schedule settings
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) `b74ef07`

## Phase 2: Cloud Identity & Discovery Engine Scheduled Sync Engine
- [x] Task: Implement `CatalogSyncService`, background scheduler, and `/api/v1/sync` & `/api/v1/groups` endpoints `c14d761`
  - [x] Write failing unit tests (`backend/tests/test_sync.py`) for syncing Discovery Engine apps, IAM bindings, Cloud Identity group lookups/memberships (`groups:lookup`, `memberships:list`, `checkTransitiveMembership`), and recording `sync_runs` in PostgreSQL
  - [x] Implement `CatalogSyncService` (`backend/app/services/sync.py`) and Cloud Identity group member listing in `backend/app/services/discovery.py`
  - [x] Implement `POST /api/v1/sync`, `GET /api/v1/sync/status`, and `GET /api/v1/groups` routers (`backend/app/routers/sync.py`, `backend/app/routers/groups.py`) and background periodic scheduler in `backend/app/main.py`
- [~] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Google Cloud Identity Authentication & PostgreSQL-Backed Catalog Queries
- [ ] Task: Update authentication and catalog services to authenticate with Cloud Identity and query PostgreSQL
  - [ ] Write failing unit and integration tests (`backend/tests/test_auth.py`, `backend/tests/test_catalog.py`, `backend/tests/test_main.py`) verifying Google OAuth / Cloud Identity token validation, user persistence in PostgreSQL, and database-backed group & app queries
  - [ ] Update `backend/app/auth.py` and `backend/app/routers/auth.py` to validate Google OAuth / Cloud Identity credentials, upsert users in PostgreSQL, and resolve user groups from PostgreSQL (with live Cloud Identity fallback)
  - [ ] Update `backend/app/services/catalog.py` and `backend/app/routers/apps.py` to query applications and group bindings directly from PostgreSQL
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Frontend Sync Status Controls & Local End-to-End Verification
- [ ] Task: Add PostgreSQL Sync Status indicator and manual Sync trigger in Frontend Header and verify live local PostgreSQL stack
  - [ ] Write failing frontend unit tests (`frontend/src/App.test.tsx`) for displaying PostgreSQL sync status and triggering on-demand sync
  - [ ] Update frontend API client and `Header.tsx` to display synced database status and a "Sync Now" control, and verify live local PostgreSQL database population and queries
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
