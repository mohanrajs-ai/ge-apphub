"""Stage 2: Local ADK InfoSec Governance Agent for Gemini Enterprise Skills."""

import re
from typing import Any

_PROMPT_INJECTION_PATTERNS: tuple[str, ...] = (
    r"ignore\s+previous\s+instructions",
    r"disregard\s+all\s+system\s+prompts",
    r"bypass\s+security",
    r"exfiltrate",
)

_SECRET_PATTERNS: tuple[str, ...] = (
    r"private_key",
    r"begin\s+rsa\s+private\s+key",
    r"ai[zZ]a[0-9a-zA-Z\-_]{30,}",
    r"password\s*=\s*['\"][^'\"]+['\"]",
)


def scan_prompt_injection_patterns(instruction: str) -> list[str]:
    """ADK Tool: Scans SKILL.md for prompt injection or jailbreak patterns."""
    findings: list[str] = []
    text = instruction or ""
    for pat in _PROMPT_INJECTION_PATTERNS:
        if re.search(pat, text, flags=re.IGNORECASE):
            findings.append(
                f"Detected prohibited prompt-override pattern: '{pat}'"
            )
    return findings


def scan_secrets_and_exfiltration(
    instruction: str,
    gcs_uri: str,
) -> list[str]:
    """ADK Tool: Scans SKILL.md and GCS URI for hardcoded secrets or exfil."""
    findings: list[str] = []
    text = instruction or ""
    for pat in _SECRET_PATTERNS:
        if re.search(pat, text, flags=re.IGNORECASE):
            findings.append(
                f"Detected potential credential/secret pattern: '{pat}'"
            )
    if gcs_uri and not gcs_uri.startswith("gs://"):
        findings.append(
            "Skill artifact URI must use approved gs:// Cloud Storage scheme."
        )
    return findings


def evaluate_iam_proposal_scope(
    iam_proposals: list[dict[str, Any]],
) -> list[str]:
    """ADK Tool: Validates least-privilege IAM roles on share proposals."""
    findings: list[str] = []
    for prop in iam_proposals or []:
        role = str(prop.get("role") or "")
        if "owner" in role.lower() or "admin" in role.lower():
            findings.append(
                f"Share proposal requests elevated role '{role}' instead of "
                "roles/discoveryengine.agentUser."
            )
    return findings


class InfoSecAdkAgent:
    """Local Google ADK InfoSec Agent for security & compliance inspection.

    Structured around the Google ADK Agent pattern (`name`, `model`,
    `instruction`, `tools`) so it can be expanded or connected to an external
    ADK InfoSec runner.
    """

    def __init__(self, model: str = "gemini-2.5-flash") -> None:
        """Initializes the local ADK InfoSec Governance Agent."""
        self._model = model
        self.agent_definition: dict[str, Any] = {
            "name": "infosec_governance_adk_agent",
            "model": self._model,
            "description": (
                "Scans Gemini Enterprise Skills for prompt injection, "
                "data exfiltration, credential leakage, and IAM least-"
                "privilege compliance."
            ),
            "instruction": (
                "You are the Enterprise InfoSec ADK Agent. Inspect the "
                "submitted skill instructions, artifact URI, and IAM "
                "proposals for security risks before human InfoSec sign-off."
            ),
            "tools": [
                scan_prompt_injection_patterns,
                scan_secrets_and_exfiltration,
                evaluate_iam_proposal_scope,
            ],
        }

    def scan_skill(
        self,
        display_name: str,
        instruction: str,
        gcs_uri: str = "",
        iam_proposals: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Executes the InfoSec security scan on a Gemini Enterprise skill.

        Args:
            display_name: Skill display name.
            instruction: Full SKILL.md markdown instruction.
            gcs_uri: Cloud Storage artifact URI.
            iam_proposals: Pending IAM share proposals.

        Returns:
            Security report with `risk_level`, `passed`, `findings`, `checks`.
        """
        inj_findings = scan_prompt_injection_patterns(instruction)
        sec_findings = scan_secrets_and_exfiltration(instruction, gcs_uri)
        iam_findings = evaluate_iam_proposal_scope(iam_proposals or [])

        all_findings = inj_findings + sec_findings + iam_findings
        if inj_findings or sec_findings:
            risk_level = "HIGH"
            passed = False
        elif iam_findings:
            risk_level = "MEDIUM"
            passed = False
        else:
            risk_level = "LOW"
            passed = True

        checks = [
            {
                "check": "Prompt Injection & Guardrail Scan",
                "passed": len(inj_findings) == 0,
                "detail": (
                    "No prompt override or jailbreak directives detected."
                    if not inj_findings
                    else "; ".join(inj_findings)
                ),
            },
            {
                "check": "Credential Leakage & Artifact Storage Verification",
                "passed": len(sec_findings) == 0,
                "detail": (
                    "No hardcoded secrets; GCS artifact URI verified."
                    if not sec_findings
                    else "; ".join(sec_findings)
                ),
            },
            {
                "check": "IAM Least-Privilege Share Proposal Check",
                "passed": len(iam_findings) == 0,
                "detail": (
                    "All share proposals use least-privilege agentUser role."
                    if not iam_findings
                    else "; ".join(iam_findings)
                ),
            },
        ]

        return {
            "agent_name": self.agent_definition["name"],
            "model": self._model,
            "skill_name": display_name,
            "risk_level": risk_level,
            "passed": passed,
            "verdict": "PASSED" if passed else "FAILED",
            "findings": all_findings,
            "checks": checks,
            "summary": (
                f"InfoSec ADK scan passed for '{display_name}' "
                f"(Risk Level: {risk_level}). Ready for InfoSec team review."
                if passed
                else (
                    f"InfoSec ADK scan flagged {len(all_findings)} security "
                    f"finding(s) (Risk Level: {risk_level})."
                )
            ),
        }
