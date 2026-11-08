# Enterprise Deployment Guide: Google Cloud Gemini Enterprise + Microsoft 365 & Entra ID SSO

This guide provides the complete, step-by-step runbook to deploy **Google Cloud Gemini Enterprise (Discovery Engine)** integrated with **Microsoft Entra ID (SAML 2.0 Single Sign-On + Group Sync)** and **Microsoft 365 Connectors (SharePoint Online, OneDrive, Outlook, and Microsoft Teams)** for any enterprise organization (e.g., `techmahindra.com`, `contoso.com`, etc.).

---

## 1. Architecture Overview

```text
Microsoft Entra ID (Corporate Tenant — e.g., techmahindra.com)
  ├── Corporate Users (*@<company-domain>)
  ├── Department Security Groups (e.g., ge-finance-users, ge-hr-users, ...)
  ├── SAML 2.0 Enterprise App ("Google Cloud / G Suite Connector by Microsoft")
  └── OAuth 2.0 App Registration (for M365 Connectors & Graph Identity Sync)
         │
         ▼  (1:1 Group Sync + Inbound SAML SSO Profile Redirect)
Google Cloud Identity (customers/C0xxxxxxx)
  ├── Verified Corporate Domain (<company-domain>)
  ├── Synced Entra Groups: ge-<dept>-users@<company-domain>
  └── Nested 1:1 into Per-App Access Groups: <app-id>-users@<company-domain>
         │
         ▼  (Exclusive Engine-Level IAM + Least-Privilege Connector OAuth Role: geConnectorAuthUser)
Google Cloud Project (<GCP_PROJECT_ID>)
  ├── Isolated Department Gemini Enterprise Apps (Finance, HR, Marketing, Ops, Sales, Service Desk, ...)
  ├── Shared M365 Federated + Write-Action Connectors (SharePoint, OneDrive, Outlook, Teams)
  └── Secret Manager JSON Credentials (projects/<GCP_PROJECT_ID>/secrets/m365-connector-credentials)
```

---

## 2. Pre-Deployment Customer Discovery Checklist

Collect these **8 parameters** before starting the deployment:

| # | Parameter | Variable Name | Example (e.g., Tech Mahindra) |
| :- | :--- | :--- | :--- |
| 1 | **GCP Project ID** | `GCP_PROJECT_ID` | `techm-gemini-enterprise-prod` |
| 2 | **GCP Organization ID** | `GCP_ORG_ID` | `123456789012` |
| 3 | **Cloud Identity Customer ID** | `CLOUD_IDENTITY_CUSTOMER_ID` | `customers/C01234567` *(from `admin.google.com` -> Account -> Account settings)* |
| 4 | **Corporate Domain** | `PRIMARY_CUSTOMER_DOMAIN` / `SHARED_IDENTITY_DOMAIN` | `techmahindra.com` |
| 5 | **Microsoft Entra Tenant ID** | `M365_TENANT_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| 6 | **SharePoint Root URL** | `M365_SHAREPOINT_INSTANCE_URI` | `https://techmahindra.sharepoint.com` |
| 7 | **OneDrive Root URL** | `M365_ONEDRIVE_INSTANCE_URI` | `https://techmahindra-my.sharepoint.com` |
| 8 | **Department Apps & Entra Groups** | `ENTRA_TO_APP_GROUP_MAPPINGS` | `ge-finance-users@techmahindra.com:finance-app-01-users@techmahindra.com,...` |

### Workstation Prerequisites
* `gcloud` CLI authenticated (`gcloud auth login` and `gcloud auth application-default login`)
* `terraform` >= 1.5
* `jq` and `curl`

---

## 3. Step 1: Microsoft Entra ID Setup (One-Time Admin Configuration)

You need **two** items in **[Microsoft Entra Admin Center (`entra.microsoft.com`)](https://entra.microsoft.com)**:
1. An **App Registration** (OAuth 2.0) for the M365 Data Connectors and Microsoft Graph Group Sync.
2. An **Enterprise Application** (SAML 2.0) from the Entra Gallery to redirect Google Cloud login to Microsoft Entra ID.

### 1A. Create the OAuth 2.0 App Registration (for M365 Connectors & Graph Sync)
1. Go to **Identity** -> **Applications** -> **App registrations** -> **+ New registration**:
   * **Name:** `gemini-enterprise-m365-connector`
   * **Supported account types:** *Accounts in this organizational directory only (Single tenant)*
   * **Redirect URI:** Select **Web** and enter:
     ```text
     https://vertexaisearch.cloud.google.com/oauth-redirect
     ```
   * Click **Register** and copy the **Application (client) ID** and **Directory (tenant) ID**.
2. Go to **Certificates & secrets** -> **+ New client secret** -> create a secret and copy its **Value** (`client_secret`).
3. Go to **API permissions** -> **+ Add a permission** and add both **Application** and **Delegated** permissions below:

   * **Microsoft Graph — Application permissions** *(for Entra Group Sync & M365 Connector background metadata)*:
     * `User.Read.All` *(or `User.ReadWrite.All` if migrating sandbox UPNs)*
     * `Group.Read.All` *(or `Group.ReadWrite.All` if creating groups via script)*
     * `GroupMember.Read.All`
     * `Sites.Read.All`
     * `Files.Read.All`
     * `Mail.Read`
   * **Microsoft Graph — Delegated permissions** *(required for End-User 3-Legged OAuth on Outlook, Teams, OneDrive)*:
     * **OpenId:** `openid`, `profile`, `offline_access`, `User.Read`
     * **Outlook Mail / Calendar / Contacts:** `Mail.ReadWrite`, `Mail.ReadWrite.Shared`, `Mail.Send`, `Mail.Send.Shared`, `Calendars.ReadWrite`, `Contacts.ReadWrite`
     * **OneDrive / SharePoint Files:** `Files.ReadWrite.All`, `Sites.ReadWrite.All`
     * **Microsoft Teams:** `Chat.Read`, `Chat.ReadWrite`, `ChannelMessage.Read.All`, `ChannelMessage.Send`, `Team.ReadBasic.All`, `Channel.ReadBasic.All`, `Channel.Create`
   * **SharePoint (Office 365 SharePoint Online) — Delegated permissions** *(required for SharePoint Federated Search)*:
     * `AllSites.Read` (or `AllSites.Write`)
     * `MyFiles.Read`
4. Click **"Grant admin consent for <Organization>"** at the top of the **API permissions** table and confirm all rows show a green checkmark.

---

### 1B. Create the SAML 2.0 Gallery App (for Entra ID Login Redirect)
> **Important:** Do **not** use the App Registration above for SAML SSO (SAML is greyed out on App Registrations). Always create the official gallery app under **Enterprise applications**:

1. In **[entra.microsoft.com](https://entra.microsoft.com)**, go to **Identity** -> **Applications** -> **Enterprise applications** -> **+ New application**.
2. Search for:
   ```text
   Google Cloud / G Suite Connector by Microsoft
   ```
3. Select the tile and click **Create**.
4. Go to **Manage -> Users and groups** -> **+ Add user/group** -> assign the corporate users or department security groups (`ge-finance-users`, `ge-hr-users`, etc.) who should access Gemini Enterprise.
   *(Leave the **Single sign-on** page open—you will paste the Google SP Entity ID and ACS URL generated in Step 2 below).*

---

## 4. Step 2: Export & Validate M365 Secret Environment Variables, Then Deploy M365 Connectors (`deploy_m365.sh`)

1. **Export your Microsoft Entra ID credentials as shell environment variables** (never hardcode secrets in `.env` files):
   ```bash
   export M365_TENANT_ID="<your-entra-tenant-id>"
   export M365_CLIENT_ID="<your-entra-app-client-id>"
   export M365_CLIENT_SECRET="<your-entra-app-client-secret>"
   ```
2. **Validate the environment variables and Entra ID OAuth credentials before proceeding:**
   ```bash
   # Verify all three environment variables are set and non-empty
   for var in M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET; do
     [[ -n "${!var:-}" ]] && echo "[OK] ${var} is set" || { echo "[ERROR] ${var} is NOT set"; exit 1; }
   done

   # Validate OAuth2 client_credentials handshake against Microsoft Identity Platform
   curl -sS -X POST "https://login.microsoftonline.com/${M365_TENANT_ID}/oauth2/v2.0/token" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     --data-urlencode "client_id=${M365_CLIENT_ID}" \
     --data-urlencode "client_secret=${M365_CLIENT_SECRET}" \
     --data-urlencode "scope=https://graph.microsoft.com/.default" \
     --data-urlencode "grant_type=client_credentials" \
     | jq -e '.access_token != null' >/dev/null \
     && echo "[OK] Microsoft Entra ID credentials validated" \
     || echo "[ERROR] Microsoft Entra ID credential validation failed"
   ```
3. Copy the M365 configuration template and common connectors registry:
   ```bash
   cp configs/m365.env.example configs/m365.env
   cp configs/common_connectors.env.example configs/common_connectors.env
   ```
4. Edit `configs/m365.env` and set your non-secret customer values (`M365_TENANT_ID`, `M365_CLIENT_ID`, and `M365_CLIENT_SECRET` are automatically inherited from your exported environment variables):
   ```bash
   GCP_PROJECT_ID="techm-gemini-enterprise-prod"
   M365_SHAREPOINT_INSTANCE_URI="https://techmahindra.sharepoint.com"
   M365_ONEDRIVE_INSTANCE_URI="https://techmahindra-my.sharepoint.com"
   ```
5. Run pre-flight dry-run validation, then execute the M365 Connectors orchestrator:
   ```bash
   ./deploy_m365.sh --config configs/m365.env --dry-run
   ./deploy_m365.sh --config configs/m365.env
   ```
   **What this automates:**
   * Validates that `M365_TENANT_ID`, `M365_CLIENT_ID`, and `M365_CLIENT_SECRET` are present in the environment before proceeding.
   * Synchronizes Secret Manager secret `projects/<GCP_PROJECT_ID>/secrets/m365-connector-credentials` from the environment variables.
   * Provisions all 4 M365 connectors (`m365-sp`, `m365-od`, `m365-ol`, `m365-teams`) in `FEDERATED` + `ACTIONS` mode with `o365_environment_type="com"`.

---

## 5. Step 3: Deploy Department Gemini Enterprise Apps & Per-App IAM (`deploy.sh`)

1. Create a `.env` file per department app (or copy `config.env.example`):
   ```bash
   cp config.env.example configs/finance-app.env
   ```
2. Populate `configs/finance-app.env`:
   ```bash
   GCP_PROJECT_ID="techm-gemini-enterprise-prod"
   GE_APP_ID="finance-app-01"
   GE_APP_DISPLAY_NAME="Gemini Finance App"
   GE_COMPANY_NAME="Tech Mahindra"
   GE_DATA_STORE_ID="finance-app-knowledge-ds-01"
   GE_GCS_BUCKET_NAME="techm-ge-finance-docs-01"
   GE_CUSTOMER_DOMAIN="techmahindra.com"
   GE_CLOUD_IDENTITY_CUSTOMER_ID="customers/C01234567"
   GE_APP_ACCESS_GROUP="finance-app-01-users@techmahindra.com"
   ```
3. Deploy each department app:
   ```bash
   ./deploy.sh --config configs/finance-app.env
   ```
   **What this automates:**
   * Enables required GCP APIs, provisions the backing GCS/BigQuery store, Data Store, and Gemini Enterprise Engine (`finance-app-01`).
   * Automatically attaches all 9 M365 entity Data Stores (`m365-sp_file`, `m365-sp_page`, `m365-od_file`, `m365-ol_mail`, `m365-ol_mail-attachment`, `m365-ol_calendar`, `m365-ol_contact`, `m365-teams_channel-message`, `m365-teams_chat-message`) from `configs/common_connectors.env`.
   * Creates the dedicated Cloud Identity group `finance-app-01-users@techmahindra.com` and enforces **exclusive Engine-level IAM** (`:setIamPolicy`) on `finance-app-01`.
   * Creates the least-privilege custom role `projects/<GCP_PROJECT_ID>/roles/geConnectorAuthUser` (`discoveryengine.locations.buildAuthorizationUrl`, `discoveryengine.dataConnectors.*`) and grants Collection-level IAM on all 4 M365 connector collections so users can authorize M365 connectors without `403 Forbidden` while remaining strictly isolated from other department apps.

---

## 6. Step 4: Sync Entra ID Groups & Enable SAML 2.0 SSO Redirect (`deploy_identity.sh`)

1. Ensure the M365 secret environment variables are exported and validated in your current shell session:
   ```bash
   export M365_TENANT_ID="<your-entra-tenant-id>"
   export M365_CLIENT_ID="<your-entra-app-client-id>"
   export M365_CLIENT_SECRET="<your-entra-app-client-secret>"

   for var in M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET; do
     [[ -n "${!var:-}" ]] && echo "[OK] ${var} is set" || { echo "[ERROR] ${var} is NOT set"; exit 1; }
   done
   ```
2. Copy the identity configuration template:
   ```bash
   cp configs/identity.env.example configs/identity.env
   ```
3. Populate `configs/identity.env`:
   ```bash
   GCP_PROJECT_ID="techm-gemini-enterprise-prod"
   GCP_ORG_ID="123456789012"
   CLOUD_IDENTITY_CUSTOMER_ID="customers/C01234567"
   PRIMARY_CUSTOMER_DOMAIN="techmahindra.com"
   SHARED_IDENTITY_DOMAIN="techmahindra.com"
   M365_SECRET_ID="m365-connector-credentials"

   # Map your Entra ID Security Groups 1:1 into each Gemini Enterprise App's access group:
   ENTRA_GROUP_FILTER="startswith(mailNickname,'ge-')"
   ENTRA_TO_APP_GROUP_MAPPINGS="ge-finance-users@techmahindra.com:finance-app-01-users@techmahindra.com,ge-hr-users@techmahindra.com:hr-app-01-users@techmahindra.com"

   # Automatically create the Cloud Identity Inbound SAML SSO Profile:
   ENABLE_CLOUD_IDENTITY_SAML_SSO="true"
   SAML_SSO_PROFILE_DISPLAY_NAME="Microsoft Entra ID SSO"
   ```
4. Validate configuration with `--dry-run`, then run the Identity Sync & SSO orchestrator:
   ```bash
   ./deploy_identity.sh --config configs/identity.env --dry-run
   ./deploy_identity.sh --config configs/identity.env
   ```
   **What this automates:**
   * Reads Entra ID credentials from Secret Manager (`m365-connector-credentials`).
   * Queries Microsoft Graph for your Entra ID groups & transitive user memberships, exports `configs/cloud_identity_users.csv` (for optional bulk user import in `admin.google.com` if Google Cloud Directory Sync / Entra provisioning is not yet enabled), creates matching groups in Cloud Identity, and nests them 1:1 into your Gemini Enterprise per-app groups (`finance-app-01-users@techmahindra.com`, etc.).
   * Creates the **Cloud Identity Inbound SAML SSO Profile** (`Microsoft Entra ID SSO`) pre-configured with your Entra Tenant's Entity ID and Login URL, and outputs the generated **SP Entity ID** and **SP ACS (Reply) URL**:
     ```text
     SAML SP Entity ID         : https://accounts.google.com/samlrp/<profile-id>
     SAML SP ACS (Reply) URL   : https://accounts.google.com/samlrp/<profile-id>/acs
     ```
4. **Complete the SAML Handshake Between Entra ID and Cloud Identity:**
   * In **Microsoft Entra Admin Center** -> **Enterprise applications** -> **Google Cloud / G Suite Connector by Microsoft** -> **Single sign-on** -> **SAML**:
     * **Identifier (Entity ID):** Paste `https://accounts.google.com/samlrp/<profile-id>` (mark as Default).
     * **Reply URL (ACS URL):** Paste `https://accounts.google.com/samlrp/<profile-id>/acs` (mark as Default).
     * **Sign on URL:** `https://www.google.com/a/<company-domain>/ServiceLogin?continue=https://vertexaisearch.cloud.google.com`
     * Download **Certificate (Base64)** (`.cer` file).
   * Either set `SAML_IDP_CERT_FILE="/path/to/downloaded.cer"` in `configs/identity.env` and re-run `./deploy_identity.sh --config configs/identity.env --curl-only`, **or** upload the `.cer` file in **[admin.google.com](https://admin.google.com)** -> **Security** -> **Authentication** -> **SSO with third-party IdP** -> **Third-party SSO profiles** -> **`Microsoft Entra ID SSO`**, and assign the SSO profile under **Manage SSO profile assignments**.

---

## 7. End-to-End Validation & Troubleshooting Runbook

### Validation Checklist
1. **Entra ID SAML Redirect:** Open an Incognito browser window to the Gemini Enterprise Web App URL (`https://vertexaisearch.cloud.google.com/home/cid/<configId>`). Enter `<user>@<company-domain>`—verify Google immediately redirects to `login.microsoftonline.com` without prompting for a Google password.
2. **M365 Connector OAuth Authorization:** Inside the Gemini Enterprise Web App, click **Authorize** on **Outlook**, **Microsoft Teams**, **OneDrive**, and **SharePoint**—verify the popup reuses your active Entra ID session and completes without error.
3. **Per-App Department Isolation:** Sign in as a Finance user and attempt to open the HR App URL—verify access is denied.

### Common Troubleshooting Reference

| Symptom | Root Cause | Resolution |
| :--- | :--- | :--- |
| **`POST .../widgetBuildAuthorizationUrl 403 (Forbidden)`** in browser console when clicking **Authorize** | User's group only has Engine-level IAM and lacks `discoveryengine.locations.buildAuthorizationUrl` on the project or Collection IAM on `collections/m365-*` | Handled automatically by `configure_connector_oauth_iam()` in `scripts/configure_ge_app.sh` (`geConnectorAuthUser` custom role + Collection `:setIamPolicy`). Re-run `./deploy.sh --config <app>.env --curl-only`. |
| **Outlook / OneDrive popup opens `https://login.microsoftonline.Commercial/...`** (`DNS_PROBE_FINISHED_NXDOMAIN`) | `o365_environment_type` was set to `"Commercial"` instead of `"com"` | Handled automatically in `scripts/configure_m365_connectors.sh` and `terraform-m365/m365_connectors.tf` (`o365_environment_type = "com"`). |
| **Microsoft Teams / Calendar authorization fails after Entra login** | Missing **Delegated** permissions on the Entra App Registration | Add the **Delegated** permissions listed in **Step 1A** (`Chat.ReadWrite`, `ChannelMessage.Read.All`, `ChannelMessage.Send`, `Calendars.ReadWrite`, `Contacts.ReadWrite`, `offline_access`) and click **Grant admin consent**. |
| **SAML option is greyed out in Microsoft Entra ID** | Opened the OAuth App Registration under *Enterprise applications* instead of a Gallery SAML app | Follow **Step 1B**: go to **Enterprise applications -> + New application** and add **Google Cloud / G Suite Connector by Microsoft** from the Entra gallery. |
| **Cloud Identity Terraform `Error(2028)` when adding group members** | Target `@<company-domain>` user accounts do not exist in Cloud Identity yet | Upload the auto-generated `configs/cloud_identity_users.csv` in `admin.google.com -> Directory -> Users -> Bulk update users` (or enable Entra ID automatic user provisioning to Google Cloud). |
