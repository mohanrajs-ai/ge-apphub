---
name: stock-deep-research-5yr-forecast-engine
description: Universal-Orchestrator-compatible institutional equity research skill that accepts any stock ticker or company name, retrieves the last 5 years of financial statements (Income Statement, Balance Sheet, Cash Flow), performs deep Fundamental, Technical, and Sentiment analysis, runs a 2-model time-series forecast for the next 5 years YoY growth in Python (`execute_python_equity_quant_forecast`), and issues an institutional Buy/Hold/Sell recommendation with target price.
sub_skills:
  - m365-onedrive-artifact-finder
  - sharepoint-policy-lookup
  - m365-outlook-triage
---

# Composite Skill: Institutional Stock Deep Research & 5-Year YoY Growth Forecaster (`stock-deep-research-5yr-forecast-engine`)

> **Runtime Requirement:** Designed for the **Universal ADK Skill Orchestrator (`universal-skill-orchestrator`)** on Vertex AI `ReasoningEngine`. Executes deterministic Python quantitative financial modeling and time-series forecasting via `execute_python_equity_quant_forecast`.

## When to Use
Use this skill whenever a user provides **any stock name or ticker symbol** (e.g., `NVDA`, `MSFT`, `GOOGL`, `AAPL`, `AMZN`, `TSLA`, or any public equity) and requests:
- Last 5 years of financial statements (Revenue, Gross/Operating/Net Margin, EPS, Free Cash Flow, Balance Sheet ratios)
- Deep **Fundamental Analysis** (CAGR, ROE, ROIC, Debt/Equity, DCF Intrinsic Valuation)
- **Technical Analysis** (50d/200d SMA, 14d RSI, MACD, Volatility, Sharpe Ratio, Support/Resistance)
- **Sentiment Analysis** (Earnings transcript tone, institutional analyst consensus, M365 research desk sentiment)
- **Next 5 Years YoY Growth Forecast** (`FY2026E`–`FY2030E` Revenue, EPS, FCF, and YoY % growth using chronological train/validation model comparison)
- **Actionable Buy / Hold / Sell Recommendation** with 12-month Target Price, Implied Upside %, and Bull/Base/Bear cases.

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `m365-onedrive-connector`, `m365-sharepoint-connector`, `m365-outlook-connector`
- **Delegated Sub-Skills:** `m365-onedrive-artifact-finder`, `sharepoint-policy-lookup`, `m365-outlook-triage`
- **Required Universal Agent Python Tool:** `execute_python_equity_quant_forecast`

## Expected Input & Output
- **Input:** Any stock ticker or company name (e.g., *"Run stock-deep-research-5yr-forecast-engine for NVIDIA (NVDA)"* or *"Analyze Microsoft stock with 5-year financials, 5-year YoY forecast, and buy/sell recommendation"*).
- **Output:**
  1. **Last 5 Years Financial Statements Table (`FY2021`–`FY2025`)** (Revenue, YoY Growth %, Operating Margin %, Net Income, EPS, Free Cash Flow, ROE, ROIC, Debt/Equity).
  2. **Deep Fundamental Valuation** (5-Year DCF Intrinsic Value, WACC, Margin of Safety, P/E, PEG, EV/EBITDA).
  3. **Technical Analysis Indicators** (Current Price vs. 50d/200d SMA, RSI-14, MACD, Beta, Sharpe Ratio, Support & Resistance).
  4. **Multi-Source Sentiment Analysis** (Earnings Call NLP score, Analyst Consensus, Institutional Flow, M365 Research Desk notes).
  5. **5-Year YoY Growth Forecast (`FY2026E`–`FY2030E`) & ML Model Comparison** (Chronological validation comparing Log-Linear Regression vs. Damped Holt Autoregressive Trend, with 95% confidence bounds and ASCII trajectory chart).
  6. **Final Institutional Recommendation (`STRONG BUY` / `BUY` / `HOLD` / `SELL`)**, Weighted Composite Score (`0–100`), 12-Month Price Target, and SHA-256 Investment Committee Audit Digest.

## Step-by-Step Workflow
1. **Step 1 — Retrieve 10-K Financial Workbooks & Valuation Models from OneDrive (`m365-onedrive-artifact-finder`):**
   - Call `execute_subskill("m365-onedrive-artifact-finder", task_input)` to locate internal 5-year financial statement spreadsheets and equity research models in OneDrive.
2. **Step 2 — Check Institutional Investment Committee Mandate & Risk Rules in SharePoint (`sharepoint-policy-lookup`):**
   - Call `execute_subskill("sharepoint-policy-lookup", task_input)` to retrieve institutional hurdle rates (WACC, minimum ROIC, PEG thresholds, and Buy/Sell rating criteria) from SharePoint.
3. **Step 3 — Gather Analyst Notes & Earnings Sentiment from Outlook (`m365-outlook-triage`):**
   - Call `execute_subskill("m365-outlook-triage", task_input)` to extract recent sell-side/buy-side research emails and management guidance sentiment from Outlook.
4. **Step 4 — Run Python 5-Year Financial Analysis, Technical/Sentiment Scoring & 5-Year YoY Time-Series Forecast (`execute_python_equity_quant_forecast`):**
   - Call `execute_python_equity_quant_forecast(ticker_or_company=<stock_name>, wacc_pct=9.5, terminal_growth_pct=3.5)`.
   - This executes deterministic Python code inside Vertex AI `ReasoningEngine` to:
     - Load or synthesize the 5-year historical Income Statement, Balance Sheet, and Cash Flow Statement (`FY2021`–`FY2025`).
     - Compute Fundamental ratios (CAGR, ROE, ROIC, DCF intrinsic value), Technical indicators (SMA-50/200, RSI-14, MACD, Sharpe), and Sentiment composite score.
     - Perform a chronological train/validation split (`FY2021`–`FY2024` train, `FY2025` validation) comparing **Model A (Log-Linear CAGR Regression)** vs. **Model B (Damped Autoregressive Holt Trend)**, select the lower-RMSE model, and forecast **5-Year Future YoY Growth (`FY2026E`–`FY2030E`)** with 95% confidence intervals.
     - Compute the weighted **Buy / Hold / Sell Recommendation** and cryptographic SHA-256 audit hash.
5. **Step 5 — Synthesize Institutional Equity Research Report:**
   - Present the complete 5-Year Historical Financial Table, Fundamental/Technical/Sentiment breakdown, 5-Year YoY Growth Forecast Table (`FY2026E`–`FY2030E`), ASCII Revenue Trajectory Chart, and Final Buy/Sell Recommendation.
