#!/usr/bin/env python3
"""Bundled Skill Script: Deterministic SLA Breach & FinOps Financial Exposure Calculator."""

import hashlib
import json
import math
import platform
import statistics
import sys
from typing import Any


def _percentile(sorted_vals: list[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    k = (len(sorted_vals) - 1) * (pct / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(sorted_vals[int(k)])
    return float(sorted_vals[f] * (c - k) + sorted_vals[c] * (k - f))


def calculate_sla_exposure(
    incident_id: str = "INC-2026-P1-089",
    include_histogram: bool = True,
) -> dict[str, Any]:
    """Computes exact p95/p99 latency, availability %, USD SLA credits, and SHA-256 SOX digest."""
    hourly_p99_ms = [
        165.0, 172.0, 168.0, 175.0, 180.0, 178.0,
        190.0, 640.0, 1850.0, 3420.0, 4200.0, 3890.0,
        2150.0, 780.0, 210.0, 185.0, 179.0, 174.0,
        170.0, 169.0, 173.0, 176.0, 171.0, 168.0,
    ]
    sorted_ms = sorted(hourly_p99_ms)
    mean_ms = round(statistics.mean(hourly_p99_ms), 2)
    stdev_ms = round(statistics.pstdev(hourly_p99_ms), 2)
    p50_ms = round(_percentile(sorted_ms, 50.0), 2)
    p95_ms = round(_percentile(sorted_ms, 95.0), 2)
    p99_ms = round(_percentile(sorted_ms, 99.0), 2)

    billing_month_minutes = 43200.0
    unplanned_downtime_minutes = 82.5
    actual_availability_pct = round(
        ((billing_month_minutes - unplanned_downtime_minutes) / billing_month_minutes) * 100.0,
        4,
    )
    breach_hours_500ms = sum(1 for v in hourly_p99_ms if v > 500.0)
    compound_multiplier = 1.25 if breach_hours_500ms >= 4 else 1.0

    tenants = [
        {
            "tenant_name": "Contoso Corp",
            "contact": "vp-infra@contoso.com",
            "sla_tier": "Enterprise Gold (99.90% Uptime / 500ms p99)",
            "contracted_uptime_pct": 99.90,
            "monthly_arr_usd": 185000.00,
            "base_credit_rate": 0.10,
        },
        {
            "tenant_name": "Fabrikam Bank",
            "contact": "cto@fabrikambank.com",
            "sla_tier": "Enterprise Platinum (99.95% Uptime / 300ms p99)",
            "contracted_uptime_pct": 99.95,
            "monthly_arr_usd": 320000.00,
            "base_credit_rate": 0.25,
        },
        {
            "tenant_name": "Northwind Health",
            "contact": "sre@northwindhealth.org",
            "sla_tier": "Enterprise Gold (99.90% Uptime / 500ms p99)",
            "contracted_uptime_pct": 99.90,
            "monthly_arr_usd": 95000.00,
            "base_credit_rate": 0.10,
        },
    ]

    tenant_exposures: list[dict[str, Any]] = []
    total_credit_usd = 0.0
    for t in tenants:
        breached = actual_availability_pct < t["contracted_uptime_pct"]
        effective_rate = round(
            (t["base_credit_rate"] * compound_multiplier) if breached else 0.0,
            4,
        )
        credit_usd = round(t["monthly_arr_usd"] * effective_rate, 2)
        total_credit_usd = round(total_credit_usd + credit_usd, 2)
        tenant_exposures.append(
            {
                "tenant_name": t["tenant_name"],
                "contact": t["contact"],
                "sla_tier": t["sla_tier"],
                "contracted_uptime_pct": t["contracted_uptime_pct"],
                "actual_availability_pct": actual_availability_pct,
                "sla_breached": breached,
                "monthly_arr_usd": t["monthly_arr_usd"],
                "base_credit_rate_pct": round(t["base_credit_rate"] * 100.0, 2),
                "compound_breach_multiplier": compound_multiplier,
                "effective_credit_rate_pct": round(effective_rate * 100.0, 2),
                "calculated_credit_liability_usd": credit_usd,
            }
        )

    histogram_lines = []
    if include_histogram:
        buckets = [
            ("<200ms (Nominal)", sum(1 for v in hourly_p99_ms if v < 200.0)),
            ("200-499ms (Elevated)", sum(1 for v in hourly_p99_ms if 200.0 <= v < 500.0)),
            ("500-1999ms (Breach)", sum(1 for v in hourly_p99_ms if 500.0 <= v < 2000.0)),
            (">=2000ms (Severe P1)", sum(1 for v in hourly_p99_ms if v >= 2000.0)),
        ]
        for label, count in buckets:
            histogram_lines.append(f"{label:22s} | {'█' * count} ({count}h)")

    canonical_ledger = {
        "incident_id": incident_id or "INC-2026-P1-089",
        "samples_count": len(hourly_p99_ms),
        "mean_ms": mean_ms,
        "stdev_ms": stdev_ms,
        "p50_ms": p50_ms,
        "p95_ms": p95_ms,
        "p99_ms": p99_ms,
        "actual_availability_pct": actual_availability_pct,
        "breach_hours_gt_500ms": breach_hours_500ms,
        "compound_multiplier": compound_multiplier,
        "total_credit_liability_usd": total_credit_usd,
        "tenant_exposures": tenant_exposures,
    }
    sha256_digest = hashlib.sha256(
        json.dumps(canonical_ledger, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    return {
        "script": "scripts/sla_finops_calculator.py",
        "python_version": platform.python_version(),
        "incident_id": canonical_ledger["incident_id"],
        "telemetry_statistics": {
            "sample_hours": len(hourly_p99_ms),
            "mean_latency_ms": mean_ms,
            "std_dev_latency_ms": stdev_ms,
            "p50_latency_ms": p50_ms,
            "p95_latency_ms": p95_ms,
            "p99_latency_ms": p99_ms,
            "breach_hours_gt_500ms": breach_hours_500ms,
            "unplanned_downtime_minutes": unplanned_downtime_minutes,
            "billing_month_minutes": billing_month_minutes,
            "actual_availability_pct": actual_availability_pct,
        },
        "ascii_latency_histogram": "\n".join(histogram_lines),
        "tenant_financial_exposures": tenant_exposures,
        "total_portfolio_sla_credit_usd": total_credit_usd,
        "sha256_sox_audit_digest": sha256_digest,
    }


if __name__ == "__main__":
    raw = sys.stdin.read().strip() if not sys.stdin.isatty() else "{}"
    payload = json.loads(raw or "{}")
    result = calculate_sla_exposure(
        incident_id=payload.get("incident_id", "INC-2026-P1-089"),
        include_histogram=bool(payload.get("include_histogram", True)),
    )
    print(json.dumps(result, indent=2))
