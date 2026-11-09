---
name: sla-breach-financial-exposure-calculator
description: Universal-Agent-Exclusive composite skill that chains M365 OneDrive telemetry, SharePoint SLA contracts, and Outlook customer claims with live Python code execution (`execute_python_sla_finops_analysis`) to compute exact p95/p99 percentiles, contractual availability %, USD credit liability, and a SOX-compliant SHA-256 audit hash.
sub_skills:
  - m365-onedrive-artifact-finder
  - sharepoint-policy-lookup
  - m365-outlook-triage
---

# Composite Skill: SLA Breach & FinOps Financial Exposure Calculator (Universal Agent Exclusive)

> **Runtime Requirement:** This skill requires the **Universal ADK Skill Orchestrator (`universal-skill-orchestrator`)** running on Vertex AI Agent Engine (`ReasoningEngine`) because Step 4 executes deterministic Python code (`execute_python_sla_finops_analysis` using Python `statistics`, `math`, and `hashlib.sha256`). It **cannot** be completed by the Gemini Enterprise `default_assistant` alone, which lacks a Python execution runtime and custom ADK tools.

## When to Use
Use this skill when Finance, SRE, or Executive leadership needs an exact, SOX-auditable calculation of SLA breach minutes, p95/p99 latency percentiles, contractual uptime percentage, and exact USD service credit exposure across affected enterprise customers following a P1/P2 production incident.

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `m365-onedrive-connector`, `m365-sharepoint-connector`, `m365-outlook-connector`
- **Delegated Sub-Skills:** `m365-onedrive-artifact-finder`, `sharepoint-policy-lookup`, `m365-outlook-triage`
- **Required Universal Agent Python Tool:** `execute_python_sla_finops_analysis`

## Expected Input & Output
- **Input:** Incident ID or incident description (e.g., *"Calculate exact SLA financial exposure and SHA-256 audit ledger for the P1 API Latency incident across Contoso, Fabrikam, and Northwind"*).
- **Output:**
  1. Grounded M365 telemetry, SLA policy rules, and customer ARR claims.
  2. Live Python execution output (`python_runtime_version`, exact p95/p99 latency, availability %, per-tenant USD credit liability, ASCII latency histogram, and `sha256_sox_audit_digest`).
  3. CFO/VP Engineering credit approval memo.

## Step-by-Step Workflow
1. **Step 1 — Fetch Raw Incident Telemetry from OneDrive (`m365-onedrive-artifact-finder`):**
   - Call `execute_subskill("m365-onedrive-artifact-finder", task_input)` to retrieve the raw hourly latency array and error-rate telemetry from `API-Latency-p99-Metrics.xlsx` in OneDrive.
2. **Step 2 — Retrieve Contractual SLA Penalty Formulas from SharePoint (`sharepoint-policy-lookup`):**
   - Call `execute_subskill("sharepoint-policy-lookup", task_input)` to fetch the Gold/Platinum uptime thresholds, compound consecutive-hour breach multipliers, and credit cap clauses from `Enterprise-SLA-Policy-v4.2.docx`.
3. **Step 3 — Extract Customer Escalation Claims & ARR Tiers from Outlook (`m365-outlook-triage`):**
   - Call `execute_subskill("m365-outlook-triage", task_input)` to identify which enterprise tenants filed P1 SLA credit claims in Outlook.
4. **Step 4 — Execute Deterministic Python FinOps & Statistical Analysis (`execute_python_sla_finops_analysis`):**
   - Call `execute_python_sla_finops_analysis(incident_id="INC-2026-P1-089", include_histogram=True)` in the Universal ADK Agent runtime.
   - This tool runs real Python 3 code (`statistics`, `math`, `hashlib.sha256`) on the telemetry samples to compute exact p95/p99 latency, downtime minutes, contractual availability %, USD credit liability per customer, and a cryptographic SHA-256 SOX audit digest.
5. **Step 5 — Synthesize Executive FinOps & SLA Credit Memo:**
   - Present the per-tenant financial exposure table, the ASCII latency distribution chart, the exact `sha256_sox_audit_digest`, and a note explaining why this calculation required the Universal ADK Agent's Python runtime.
