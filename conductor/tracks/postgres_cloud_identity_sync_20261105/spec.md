# Specification: PostgreSQL Persistence, Cloud Identity Auth & Scheduled Sync (`postgres_cloud_identity_sync_20261105`)

## 1. Overview
This track introduces a relational **PostgreSQL** database layer, **Google Cloud Identity backend authentication**, and a **scheduled synchronization engine** for **Tech-M Gemini AI Hub (`ge-apphub`)**, starting with a fully working local PostgreSQL setup.

Instead of querying Google Cloud Discovery Engine and Cloud Identity APIs on every request, a configurable background scheduler periodically synchronizes all Gemini Enterprise (GE) applications, engine IAM policies, Cloud Identity groups, and user-group memberships into PostgreSQL. The backend authenticates users via Google OAuth 2.0 / Cloud Identity (OIDC ID tokens, Cloud IAP headers, or local Workspace account login) and queries the PostgreSQL database to serve user groups, authorized applications, and sync status with low latency.

## 2. Functional Requirements

### 2.1 Local PostgreSQL Setup & Relational Schema (`/backend`, `docker-compose.yml`)
- **Local PostgreSQL Provisioning:**
  - Local PostgreSQL service installed and running on macOS (via Homebrew `postgresql@16`) with database `geapphub` and configurable `DATABASE_URL` (defaulting to `postgresql+psycopg://localhost:5432/geapphub`), plus a `docker-compose.yml` for containerized PostgreSQL setups.
  - SQLAlchemy 2.0 ORM (`app/database.py`, `app/db_models.py`) with automatic table creation on application startup and SQLite in-memory support for fast, isolated unit tests.
- **Database Tables (`app/db_models.py`):**
  - `users`: Stores `id`, `email` (unique, indexed), `user_id`, `display_name`, `roles` (JSON/array), `last_login_at`, `updated_at`.
  - `cloud_identity_groups`: Stores `id`, `group_email` (unique, indexed), `group_resource_name` (e.g., `groups/...`), `display_name`, `description`, `last_synced_at`.
  - `user_group_memberships`: Many-to-many association table linking `user_email` and `group_email` (`id`, `user_email`, `group_email`, `membership_role`, `synced_at`).
  - `ge_applications`: Stores discovered & enriched GE application records (`engine_id` primary/unique key, `display_name`, `description`, `category`, `department`, `tags` JSON, `icon_name`, `launch_url`, `default_launch_url`, `location`, `solution_type`, `industry_vertical`, `app_type`, `iam_principals` JSON, `allowed_roles` JSON, `featured`, `last_synced_at`).
  - `app_group_bindings`: Links `engine_id` to `principal` / `group_email` (`id`, `engine_id`, `principal_type`, `principal_identifier`, `synced_at`).
  - `sync_runs`: Audit log of scheduled and manual sync executions (`id`, `trigger_source`, `status`, `apps_synced`, `groups_synced`, `memberships_synced`, `error_message`, `started_at`, `completed_at`).

### 2.2 Scheduled Synchronization Service (`app/services/sync.py`, `app/routers/sync.py`)
- **Discovery Engine + Firestore + Cloud Identity Sync (`CatalogSyncService`):**
  1. Fetches all Gemini Enterprise engines and their IAM policies (`engines:getIamPolicy`) and widget launch URLs from Discovery Engine, merging optional Firestore enrichment metadata.
  2. Extracts all unique Cloud Identity group principals (`group:<email>`) referenced across engine IAM bindings.
  3. Resolves each group's Cloud Identity resource name (`groups:lookup`) and fetches group members via Cloud Identity `groups.memberships:list` (as well as verifying known Workspace users via `memberships:checkTransitiveMembership`).
  4. Upserts all `ge_applications`, `cloud_identity_groups`, `users`, `user_group_memberships`, and `app_group_bindings` into PostgreSQL within a transaction and records a `sync_runs` audit entry.
- **Defined Schedule & Lifecycle Integration:**
  - Configurable schedule via environment variables (`SYNC_ENABLED=true`, `SYNC_INTERVAL_SECONDS=900` / 15 minutes default, `SYNC_ON_STARTUP=true`).
  - Runs an initial synchronization automatically on FastAPI startup if the database is empty or `SYNC_ON_STARTUP` is enabled, and runs a background periodic scheduler loop at the defined interval.
- **Sync & Group Inspection Endpoints:**
  - `POST /api/v1/sync`: Triggers an immediate synchronization run and returns the `SyncRunResponse` summary.
  - `GET /api/v1/sync/status`: Returns the latest sync run status, schedule configuration, and database entity counts (total apps, groups, users, memberships).
  - `GET /api/v1/groups`: Queries PostgreSQL to return all synced Cloud Identity groups, their member counts, associated GE applications, and the current user's membership status.

### 2.3 Google Authentication with Cloud Identity & Database-Backed Catalog (`app/auth.py`, `app/routers/auth.py`, `app/routers/apps.py`)
- **Cloud Identity / Google OAuth 2.0 Authentication:**
  - `POST /api/v1/auth/login` verifies Google OAuth 2.0 / Cloud Identity OIDC ID tokens (`verify_oauth2_token` including `email`, `sub`, `hd` domain claim validation) or Workspace account login, upserts the authenticated `User` in PostgreSQL, and queries `user_group_memberships` from PostgreSQL.
  - If the user has no cached memberships in PostgreSQL yet, performs a live Cloud Identity transitive membership check against synced groups and persists the memberships into PostgreSQL.
- **Database-Backed Application & Group Queries:**
  - `GET /api/v1/apps` and `CatalogService` query `ge_applications` and `user_group_memberships` directly from PostgreSQL (triggering an automatic initial sync if the database has not been seeded yet).
  - `GET /api/v1/me` returns the user's identity and latest synced Cloud Identity groups from PostgreSQL.
- **Frontend Sync Status & Group Indicator:**
  - Header/UI displays the active PostgreSQL sync status and allows triggering an on-demand sync (`POST /api/v1/sync`).

## 3. Non-Functional Requirements
- **Test-Driven Development:** >80% test coverage across backend (`pytest`) and frontend (`vitest`).
- **Low Latency:** Database-backed `/api/v1/apps` and `/api/v1/groups` queries complete in <50ms locally without waiting on live Google Cloud API round-trips.
- **Resilience:** If a live Google Cloud API call fails during a scheduled sync, existing synced records in PostgreSQL remain intact and the error is logged in `sync_runs`.

## 4. Acceptance Criteria
1. Local PostgreSQL database (`geapphub`) is running and initialized with all tables (`users`, `cloud_identity_groups`, `user_group_memberships`, `ge_applications`, `app_group_bindings`, `sync_runs`).
2. Background scheduler syncs all 7 live Gemini Enterprise engines from GCP project `mohandemo`, their Cloud Identity IAM groups, and user memberships into PostgreSQL on startup and on the defined schedule.
3. Authenticating via `/api/v1/auth/login` (Google OAuth / Cloud Identity) persists the user in PostgreSQL and resolves their groups from the database (`mohanraj@mohanrajs.altostrat.com` -> 2 groups / 2 apps; `admin@mohanrajs.altostrat.com` -> 6 groups / 6 apps).
4. `GET /api/v1/apps`, `GET /api/v1/groups`, `GET /api/v1/sync/status`, and `POST /api/v1/sync` return accurate data directly from PostgreSQL.
5. All automated tests pass with >80% coverage.

## 5. Out of Scope
- Deploying Cloud SQL production infrastructure via Terraform (this track establishes the local PostgreSQL setup and application-layer ORM/sync engine first).
- Modifying Cloud Identity group memberships from within AppHub (read-only sync from Cloud Identity).
