---
name: sla-breach-financial-exposure-calculator
description: Universal-Agent-Exclusive composite skill that chains M365 OneDrive telemetry, SharePoint SLA contracts, and Outlook customer claims with the governed MCP/ADK FinOps tool (`execute_python_sla_finops_analysis`) to compute exact p95/p99 percentiles, contractual availability %, USD credit liability, and a SOX-compliant SHA-256 audit hash.
sub_skills:
  - m365-onedrive-artifact-finder
  - sharepoint-policy-lookup
  - m365-outlook-triage
---

# Composite Skill: SLA Breach & FinOps Financial Exposure Calculator (Universal Agent Exclusive)

> **Runtime Requirement:** Requires the **Universal ADK Skill Orchestrator (`universal-skill-orchestrator`)** because Step 4 invokes the governed MCP/ADK quantitative tool `execute_python_sla_finops_analysis`.

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `m365-onedrive-connector`, `m365-sharepoint-connector`, `m365-outlook-connector`
- **Delegated Sub-Skills:** `m365-onedrive-artifact-finder`, `sharepoint-policy-lookup`, `m365-outlook-triage`
- **Required Governed Tool:** `execute_python_sla_finops_analysis`

## Step-by-Step Workflow
1. **Step 1 — Fetch Raw Incident Telemetry from OneDrive (`m365-onedrive-artifact-finder`):**
   - Call `execute_subskill("m365-onedrive-artifact-finder", task_input)` to retrieve the raw hourly latency array from `API-Latency-p99-Metrics.xlsx`.
2. **Step 2 — Retrieve Contractual SLA Penalty Formulas from SharePoint (`sharepoint-policy-lookup`):**
   - Call `execute_subskill("sharepoint-policy-lookup", task_input)` to fetch the Gold/Platinum uptime thresholds from `Enterprise-SLA-Policy-v4.2.docx`.
3. **Step 3 — Extract Customer Escalation Claims & ARR Tiers from Outlook (`m365-outlook-triage`):**
   - Call `execute_subskill("m365-outlook-triage", task_input)` to identify which enterprise tenants filed P1 SLA credit claims in Outlook.
4. **Step 4 — Execute Governed FinOps & SLA Calculation Tool (`execute_python_sla_finops_analysis`):**
   - Call `execute_python_sla_finops_analysis(incident_id="INC-2026-P1-089", include_histogram=True)` to compute exact p95/p99 percentiles, contractual availability %, USD credit liability, and a SHA-256 SOX audit digest.
5. **Step 5 — Synthesize Executive FinOps & SLA Credit Memo:**
   - Present the per-tenant financial exposure table, the ASCII latency distribution chart, and the `sha256_sox_audit_digest`.
