"""Universal Enterprise Skill & Sub-Skill Orchestrator ADK Agent package."""

try:
    from app.agent import root_agent
except ImportError:
    from agents.universal_skill_orchestrator.agent import root_agent

__all__ = ["root_agent"]
