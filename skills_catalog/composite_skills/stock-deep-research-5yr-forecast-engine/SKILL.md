---
name: stock-deep-research-5yr-forecast-engine
description: Institutional equity research skill that accepts any stock ticker or company name, retrieves 5-year financial statements, performs Fundamental, Technical, and Sentiment analysis, and executes its bundled Python script (`scripts/equity_quant_forecast.py`) via `execute_skill_script` to forecast next 5 years YoY growth and issue a Buy/Hold/Sell recommendation.
sub_skills:
  - m365-onedrive-artifact-finder
  - sharepoint-policy-lookup
  - m365-outlook-triage
---

# Composite Skill: Institutional Stock Deep Research & 5-Year YoY Growth Forecaster (`stock-deep-research-5yr-forecast-engine`)

> **Runtime Requirement:** Runs on the **Universal ADK Skill Orchestrator (`universal-skill-orchestrator`)** and dynamically executes this skill's bundled Python script (`scripts/equity_quant_forecast.py`) via `execute_skill_script`.

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `m365-onedrive-connector`, `m365-sharepoint-connector`, `m365-outlook-connector`
- **Delegated Sub-Skills:** `m365-onedrive-artifact-finder`, `sharepoint-policy-lookup`, `m365-outlook-triage`
- **Bundled Python Scripts:** `scripts/equity_quant_forecast.py`

## Step-by-Step Workflow
1. **Step 1 — Retrieve 10-K Financial Workbooks from OneDrive (`m365-onedrive-artifact-finder`):**
   - Call `execute_subskill("m365-onedrive-artifact-finder", task_input)`.
2. **Step 2 — Check Institutional Investment Committee Mandate in SharePoint (`sharepoint-policy-lookup`):**
   - Call `execute_subskill("sharepoint-policy-lookup", task_input)`.
3. **Step 3 — Gather Analyst Notes & Earnings Sentiment from Outlook (`m365-outlook-triage`):**
   - Call `execute_subskill("m365-outlook-triage", task_input)`.
4. **Step 4 — Execute Bundled Python 5-Year Financials & ML Forecasting Script (`scripts/equity_quant_forecast.py`):**
   - Call `execute_skill_script(skill_id="stock-deep-research-5yr-forecast-engine", script_name="scripts/equity_quant_forecast.py", script_args_json='{"ticker_or_company": "<TICKER>", "wacc_pct": 9.5, "terminal_growth_pct": 3.5}')`.
5. **Step 5 — Synthesize Institutional Equity Research Report:**
   - Present the 5-Year Historical Financial Table, Fundamental/Technical/Sentiment breakdown, 5-Year YoY Growth Forecast Table (`FY2026E`–`FY2030E`), ASCII Revenue Trajectory Chart, and Final Buy/Sell Recommendation.
