"""Pydantic data models for the Gemini Enterprise AppHub backend."""

import pydantic


class UserContext(pydantic.BaseModel):
    """Represents the authenticated user identity and resolved roles."""

    email: str
    user_id: str
    roles: list[str]
    auth_source: str
