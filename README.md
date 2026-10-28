# Gemini Enterprise AppHub (`ge-apphub`)

Centralized enterprise marketplace and discovery portal for Gemini Enterprise (GE) applications.

## Architecture
- **Frontend (`/frontend`):** React 18, Vite, TypeScript, Tailwind CSS, Lucide Icons
- **Backend (`/backend`):** Python 3.11+, FastAPI, `google-cloud-discoveryengine` SDK, `google-cloud-firestore` SDK
- **Authentication & Visibility:** Google Cloud IAP / OAuth header resolution with local development role-preview switcher

## Quick Start

### 1. Backend API
```bash
PYTHONPATH=backend .venv/bin/uvicorn app.main:app --reload --port 8080
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
