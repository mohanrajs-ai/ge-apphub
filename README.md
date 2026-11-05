# Gemini Enterprise AppHub (`ge-apphub`)

Centralized enterprise marketplace and discovery portal for Gemini Enterprise (GE) applications.

## Architecture
- **Frontend (`/frontend`):** React 18, Vite, TypeScript, Tailwind CSS, Lucide Icons
- **Backend (`/backend`):** Python 3.11+, FastAPI, SQLAlchemy 2.0 (`psycopg`), `google-cloud-discoveryengine` SDK, `google-cloud-firestore` SDK
- **Database & Scheduled Sync:** PostgreSQL 16 (`docker-compose.yml` / `DATABASE_URL`) storing synced Gemini Enterprise applications (`ge_applications`), Cloud Identity groups (`cloud_identity_groups`), user-group memberships (`user_group_memberships`), and sync audit runs (`sync_runs`) on a configurable schedule (`SYNC_INTERVAL_SECONDS=900`)
- **Authentication & Visibility:** Google OAuth 2.0 / Cloud Identity authentication (`/api/v1/auth/login`), Google Cloud IAP header verification, and PostgreSQL-backed group visibility filtering (`/api/v1/apps`, `/api/v1/groups`, `/api/v1/sync/status`, `POST /api/v1/sync`)

## Quick Start

### 0. Local PostgreSQL Database
```bash
# Option A: Start PostgreSQL 16 via Docker Compose
docker compose up -d postgres

# Option B: Local Homebrew PostgreSQL 16
brew services start postgresql@16 && createdb geapphub
```
*(If local port `5432` is unavailable, `app/database.py` automatically falls back to local relational SQLite storage at `backend/geapphub_local.db` using the same SQLAlchemy 2.0 ORM schema.)*

### 1. Backend API
```bash
DATABASE_URL="postgresql+psycopg://localhost:5432/geapphub" \
SYNC_INTERVAL_SECONDS=900 \
PYTHONPATH=backend .venv/bin/uvicorn app.main:app --reload --port 8000
```

### 2. Frontend Development Server
```bash
cd frontend
npm run dev
```

### 3. Running Automated Tests
```bash
# Backend unit & integration tests with coverage
PYTHONPATH=backend .venv/bin/pytest backend/tests/ --cov=app --cov-report=term-missing

# Frontend unit & component tests with coverage
cd frontend && CI=true npm test -- --coverage
```
