"""Unit tests for the Universal Skill Orchestrator tools."""

import asyncio

try:
    from app.tools.skill_orchestration import (
        execute_python_equity_quant_forecast,
        execute_python_sla_finops_analysis,
        execute_subskill,
        load_skill_bundle,
    )
except ImportError:
    from agents.universal_skill_orchestrator.tools.skill_orchestration import (
        execute_python_equity_quant_forecast,
        execute_python_sla_finops_analysis,
        execute_subskill,
        load_skill_bundle,
    )


def test_skill_bundle_and_governed_mcp_tools() -> None:
    """Verifies dynamic skill bundle loading and governed MCP/ADK quantitative tools."""
    bundle = asyncio.run(
        load_skill_bundle(
            "stock-deep-research-5yr-forecast-engine",
            "cymbal-finance-app",
        )
    )
    assert bundle["skill_id"] == "stock-deep-research-5yr-forecast-engine"
    assert "execute_python_equity_quant_forecast" in bundle["required_mcp_tools"]

    sub_res = asyncio.run(
        execute_subskill(
            "sharepoint-policy-lookup",
            "Retrieve Investment Committee WACC and SLA policies",
        )
    )
    assert sub_res["status"] == "completed"

    sla_res = asyncio.run(
        execute_python_sla_finops_analysis("INC-2026-P1-089")
    )
    assert sla_res["status"] == "completed"
    assert sla_res["total_portfolio_sla_credit_usd"] == 107500.0
    assert len(sla_res["sha256_sox_audit_digest"]) == 64

    eq_res = asyncio.run(
        execute_python_equity_quant_forecast("NVDA")
    )
    assert eq_res["status"] == "completed"
    assert eq_res["investment_recommendation"]["rating"] == "STRONG BUY"
