# Gemini Enterprise + Microsoft 365 & Entra ID Deployment Template

Reusable, production-grade automation template for deploying **Google Cloud Gemini Enterprise (Discovery Engine)** integrated with **Microsoft 365 Connectors (SharePoint Online, OneDrive, Outlook, Microsoft Teams)** and **Microsoft Entra ID Single Sign-On (SAML 2.0 + 1:1 Group Sync)** in any enterprise organization.

> **Start Here for Customer Implementations:** See the complete step-by-step **[Enterprise Deployment Guide (`docs/enterprise-deployment-guide.md`)](./docs/enterprise-deployment-guide.md)**.

---

## Key Capabilities

1. **Multi-Department Gemini Enterprise Apps (`./deploy.sh`):**
   * Provisions isolated Gemini Enterprise Engines, Knowledge Data Stores, GCS/BigQuery backing storage, and Assistant instructions via Terraform (`terraform/`) and Discovery Engine REST API (`scripts/configure_ge_app.sh`).
   * Enforces **strict per-app access isolation** using dedicated Cloud Identity groups (`<app-id>-users@<domain>`) bound at the Engine resource level (`:setIamPolicy`).
   * Automatically provisions the least-privilege `geConnectorAuthUser` custom role and Collection-level IAM so non-admin users can authorize M365 connectors without cross-app leakage.
2. **Microsoft 365 Federated & Write-Action Connectors (`./deploy_m365.sh`):**
   * Provisions **SharePoint Online**, **OneDrive**, **Microsoft Outlook**, and **Microsoft Teams** connectors in `FEDERATED` + `ACTIONS` (BAP) mode (`terraform-m365/` and `scripts/configure_m365_connectors.sh`).
   * Stores Entra ID OAuth credentials (`{"tenant_id","client_id","client_secret"}`) in **Google Cloud Secret Manager** (`m365-connector-credentials`) with zero plaintext secrets in Git.
   * Automatically attaches shared M365 connector Data Stores to all Gemini Enterprise apps via `configs/common_connectors.env`.
3. **Microsoft Entra ID to Google Cloud Identity Sync & SAML SSO (`./deploy_identity.sh`):**
   * Queries Microsoft Graph for corporate Entra ID Security Groups and transitive members, syncs them 1:1 into Google Cloud Identity (`terraform-identity/` and `scripts/configure_identity.sh`), and nests them into each Gemini Enterprise app's access group.
   * Automatically provisions the **Cloud Identity Inbound SAML 2.0 SSO Profile** for Microsoft Entra ID so users signing into Gemini Enterprise are redirected directly to `login.microsoftonline.com`.

---

## Quick Start

1. **Follow the [Enterprise Deployment Guide](./docs/enterprise-deployment-guide.md)** to configure your Microsoft Entra ID OAuth App Registration and SAML Gallery App.
2. **Export & Validate M365 Secret Environment Variables, Then Deploy M365 Connectors:**
   ```bash
   export M365_TENANT_ID="<your-entra-tenant-id>"
   export M365_CLIENT_ID="<your-entra-app-client-id>"
   export M365_CLIENT_SECRET="<your-entra-app-client-secret>"

   cp configs/m365.env.example configs/m365.env
   cp configs/common_connectors.env.example configs/common_connectors.env
   ./deploy_m365.sh --config configs/m365.env --dry-run
   ./deploy_m365.sh --config configs/m365.env
   ```
3. **Configure & Deploy Gemini Enterprise Department Apps:**
   ```bash
   cp config.env.example configs/finance-app.env
   ./deploy.sh --config configs/finance-app.env
   ```
4. **Configure & Deploy Entra ID Group Sync & SAML SSO:**
   ```bash
   cp configs/identity.env.example configs/identity.env
   ./deploy_identity.sh --config configs/identity.env --dry-run
   ./deploy_identity.sh --config configs/identity.env
   ```

### CLI Modes & Required IAM Roles
All three orchestrators (`./deploy.sh`, `./deploy_m365.sh`, `./deploy_identity.sh`) support `--config <path>`, `--dry-run`, `--terraform-only`, `--curl-only`, `--verify-only`, and `--destroy`. Ensure the deploying principal holds `roles/discoveryengine.admin`, `roles/secretmanager.admin`, `roles/iam.roleAdmin`, and Cloud Identity Groups/SSO Administrator privileges.

---

## Testing & Verification

Run the built-in zero-dependency test suite (syntax checks, unit/integration tests, and line coverage):
```bash
CI=true ./tests/run_tests.sh
```
