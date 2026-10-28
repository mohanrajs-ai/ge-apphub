# Technology Stack: Gemini Enterprise AppHub (`ge-apphub`)

## 1. Programming Languages
- **Backend:** Python 3.11+
- **Frontend:** TypeScript / JavaScript (ES2022+)

## 2. Frontend Architecture
- **Framework:** React 18+ (Single Page Application built with Vite)
- **Styling & Design System:** Tailwind CSS (configured with Google Material 3 / Gemini Enterprise color tokens and dark/light theme support)
- **Icons & UI Primitives:** Lucide React / accessible headless UI primitives
- **State & Data Fetching:** TanStack Query (React Query) / Fetch API for real-time catalog filtering and search

## 3. Backend Architecture
- **Framework:** FastAPI (Python async REST API)
- **Server & Validation:** Uvicorn ASGI server with Pydantic v2 schema validation
- **Google Cloud SDK Integration:**
  - `google-cloud-discoveryengine`: Native integration with Google Cloud Discovery Engine / Gemini Enterprise APIs to dynamically list and inspect GE applications and engines.
  - `google-auth`: Application Default Credentials (ADC), Google Cloud IAM, and Enterprise SSO / IAP identity verification.

## 4. Database & Storage
- **Primary Metadata Store:** Google Cloud Firestore (`google-cloud-firestore`) — Serverless NoSQL document store used to persist custom catalog enrichment metadata (business categories, department tags, custom icons, launch URLs, and visibility rules) alongside live Discovery Engine API records.

## 5. Development, Testing & Deployment Tooling
- **Python Environment & Linting:** `uv` / `venv`, `pytest` (unit & integration testing), `ruff` (linting & formatting)
- **Frontend Tooling & Testing:** `npm`, `vitest`, React Testing Library, ESLint, Prettier
- **Target Hosting Environment:** Google Cloud Run (containerized frontend/backend deployment) with Identity-Aware Proxy (IAP) / OAuth 2.0
