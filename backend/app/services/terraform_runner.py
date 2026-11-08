"""Terraform & REST provisioning service with state isolation and plan gates."""

import datetime
import os
import pathlib
import re
import subprocess
import tempfile
import threading
import uuid
from typing import Any

from sqlalchemy import orm

from app import config
from app import db_models
from app import models

INFRA_ROOT = pathlib.Path(__file__).resolve().parents[3] / "infra"

SENSITIVE_KEYS = frozenset(
    {
        "m365_client_secret",
        "wif_oidc_client_secret",
        "client_secret",
        "cloud_identity_default_temp_password",
    }
)

_BEARER_PATTERN = re.compile(
    r"(Bearer\s+)[A-Za-z0-9._\-~+/]+=*",
    re.IGNORECASE,
)
_YA29_PATTERN = re.compile(r"ya29\.[A-Za-z0-9._\-]+")

_LOCK_GUARD = threading.Lock()
_ACTIVE_WORKSPACE_LOCKS: dict[str, str] = {}


def _utc_now() -> datetime.datetime:
    """Returns current UTC timestamp."""
    return datetime.datetime.now(datetime.timezone.utc)


def _slugify(value: str) -> str:
    """Normalizes a string into a safe Terraform workspace slug."""
    cleaned = re.sub(r"[^a-zA-Z0-9\-]+", "-", value.strip().lower()).strip("-")
    return cleaned or "default"


def acquire_workspace_lock(workspace_key: str, job_id: str) -> None:
    """Acquires an exclusive lock on a Terraform workspace key.

    Args:
        workspace_key: Target Terraform workspace identifier.
        job_id: Provisioning job ID acquiring the lock.

    Raises:
        ValueError: If another job already holds the lock for workspace_key.
    """
    with _LOCK_GUARD:
        holder = _ACTIVE_WORKSPACE_LOCKS.get(workspace_key)
        if holder and holder != job_id:
            raise ValueError(
                f"Workspace state lock for '{workspace_key}' is currently "
                f"held by active job '{holder}'."
            )
        _ACTIVE_WORKSPACE_LOCKS[workspace_key] = job_id


def release_workspace_lock(workspace_key: str, job_id: str) -> None:
    """Releases a workspace state lock if held by job_id."""
    with _LOCK_GUARD:
        if _ACTIVE_WORKSPACE_LOCKS.get(workspace_key) == job_id:
            _ACTIVE_WORKSPACE_LOCKS.pop(workspace_key, None)


def get_active_workspace_locks() -> list[str]:
    """Returns sorted list of currently locked workspace keys."""
    with _LOCK_GUARD:
        return sorted(_ACTIVE_WORKSPACE_LOCKS.keys())


def sanitize_config_dict(raw: dict[str, Any]) -> dict[str, Any]:
    """Replaces sensitive credential fields with '***REDACTED***'."""
    sanitized: dict[str, Any] = {}
    for key, val in raw.items():
        if key.lower() in SENSITIVE_KEYS or "secret" in key.lower():
            sanitized[key] = "***REDACTED***" if val else ""
        else:
            sanitized[key] = val
    return sanitized


def redact_sensitive_text(text: str, secrets: list[str]) -> str:
    """Redacts secret values and OAuth bearer tokens from log output."""
    redacted = _BEARER_PATTERN.sub(r"\1***REDACTED***", text)
    redacted = _YA29_PATTERN.sub("ya29.***REDACTED***", redacted)
    for sec in secrets:
        clean_sec = (sec or "").strip()
        if len(clean_sec) >= 4:
            redacted = redacted.replace(clean_sec, "***REDACTED***")
    return redacted


def to_job_item(record: db_models.ProvisioningJobRecord) -> (
    models.ProvisioningJobItem
):
    """Converts a ProvisioningJobRecord ORM instance to ProvisioningJobItem."""
    return models.ProvisioningJobItem(
        job_id=record.job_id,
        stack_type=record.stack_type,
        title=record.title,
        workspace_key=record.workspace_key,
        state_backend_type=record.state_backend_type,
        state_bucket=record.state_bucket,
        state_prefix=record.state_prefix,
        execution_mode=record.execution_mode,
        status=record.status,
        initiated_by=record.initiated_by,
        approved_by=record.approved_by,
        sanitized_config=dict(record.sanitized_config or {}),
        plan_summary=record.plan_summary or "",
        log_lines=list(record.log_lines or []),
        outputs=dict(record.outputs or {}),
        error_message=record.error_message,
        created_at=(
            record.created_at.isoformat() if record.created_at else None
        ),
        updated_at=(
            record.updated_at.isoformat() if record.updated_at else None
        ),
        completed_at=(
            record.completed_at.isoformat() if record.completed_at else None
        ),
    )


def _build_env_and_secrets(
    stack_type: str,
    raw_config: dict[str, Any],
    workspace_key: str,
    state_prefix: str,
) -> tuple[dict[str, str], dict[str, str], list[str]]:
    """Builds non-secret config.env entries and ephemeral secret env vars."""
    file_vars: dict[str, str] = {
        "GCP_PROJECT_ID": str(raw_config.get("gcp_project_id", "mohandemo")),
        "GCP_REGION": str(raw_config.get("gcp_region", "us-central1")),
        "GE_LOCATION": str(raw_config.get("ge_location", "global")),
        "TF_STATE_BUCKET": str(raw_config.get("tf_state_bucket", "")),
        "TF_STATE_PREFIX": state_prefix,
        "TF_WORKSPACE_OVERRIDE": workspace_key,
    }
    ephemeral_env: dict[str, str] = {
        "CLOUDSDK_METRICS_ENVIRONMENT": "geapphub",
        "TF_WORKSPACE_OVERRIDE": workspace_key,
        "TF_STATE_PREFIX": state_prefix,
    }
    secrets: list[str] = []

    for sec_key in ("m365_client_secret", "wif_oidc_client_secret"):
        val = str(raw_config.get(sec_key) or "").strip()
        if val:
            secrets.append(val)
            env_name = sec_key.upper()
            ephemeral_env[env_name] = val
            ephemeral_env[f"TF_VAR_{sec_key}"] = val

    if stack_type == "GE_APP":
        app_id = str(raw_config.get("ge_app_id", "")).strip()
        ds_id = (
            str(raw_config.get("ge_data_store_id") or "").strip()
            or f"{app_id}-ds"
        )
        app_disp = raw_config.get("ge_app_display_name", app_id)
        ds_name = (
            str(raw_config.get("ge_data_store_display_name") or "").strip()
            or f"{app_disp} Knowledge Store"
        )
        bucket = (
            str(raw_config.get("ge_gcs_bucket_name") or "").strip()
            or f"{file_vars['GCP_PROJECT_ID']}-{app_id}-docs"
        )
        file_vars.update(
            {
                "GE_APP_ID": app_id,
                "GE_APP_DISPLAY_NAME": str(
                    raw_config.get("ge_app_display_name", app_id)
                ),
                "GE_COMPANY_NAME": str(
                    raw_config.get("ge_company_name", "Enterprise Corp")
                ),
                "GE_SOLUTION_TYPE": str(
                    raw_config.get("ge_solution_type", "SOLUTION_TYPE_SEARCH")
                ),
                "GE_SEARCH_TIER": str(
                    raw_config.get("ge_search_tier", "SEARCH_TIER_ENTERPRISE")
                ),
                "GE_ENABLE_LLM_ADDON": (
                    "true"
                    if raw_config.get("ge_enable_llm_addon", True)
                    else "false"
                ),
                "GE_INDUSTRY_VERTICAL": str(
                    raw_config.get("ge_industry_vertical", "GENERIC")
                ),
                "GE_DATA_STORE_ID": ds_id,
                "GE_DATA_STORE_DISPLAY_NAME": ds_name,
                "GE_BACKING_STORAGE_TYPE": str(
                    raw_config.get("ge_backing_storage_type", "GCS")
                ),
                "GE_GCS_BUCKET_NAME": bucket,
                "GE_BQ_DATASET_ID": str(
                    raw_config.get("ge_bq_dataset_id", "gemini_enterprise_data")
                ),
                "GE_IDENTITY_PROVIDER_TYPE": str(
                    raw_config.get("ge_identity_provider_type", "GSUITE")
                ),
                "GE_WORKFORCE_IDENTITY_POOL": str(
                    raw_config.get("ge_workforce_identity_pool", "")
                ),
                "GE_CUSTOMER_DOMAIN": str(
                    raw_config.get(
                        "ge_customer_domain", "mohanrajs.altostrat.com"
                    )
                ),
                "GE_APP_ACCESS_GROUP": str(
                    raw_config.get("ge_app_access_group", "")
                ),
                "GE_APP_GROUP_MEMBERS": str(
                    raw_config.get("ge_app_group_members", "")
                ),
                "GE_ENABLE_COMMON_CONNECTORS": (
                    "true"
                    if raw_config.get("enable_common_connectors", True)
                    else "false"
                ),
                "ENABLE_AGENT_REGISTRATION": (
                    "true"
                    if raw_config.get("enable_agent_registration", False)
                    else "false"
                ),
                "AGENT_ID": str(
                    raw_config.get("agent_id", "universal-skill-orchestrator")
                ),
                "AGENT_DISPLAY_NAME": str(
                    raw_config.get(
                        "agent_display_name", "Enterprise Skill Orchestrator"
                    )
                ),
                "AGENT_DESCRIPTION": str(
                    raw_config.get("agent_description", "")
                ),
                "AGENT_REASONING_ENGINE": str(
                    raw_config.get("agent_reasoning_engine", "")
                ),
            }
        )
    elif stack_type == "IDENTITY_WIF":
        file_vars.update(
            {
                "GCP_ORG_ID": str(raw_config.get("gcp_org_id", "123456789012")),
                "CLOUD_IDENTITY_CUSTOMER_ID": str(
                    raw_config.get(
                        "cloud_identity_customer_id", "customers/C01234567"
                    )
                ),
                "PRIMARY_CUSTOMER_DOMAIN": str(
                    raw_config.get(
                        "primary_customer_domain", "mohanrajs.altostrat.com"
                    )
                ),
                "SHARED_IDENTITY_DOMAIN": str(
                    raw_config.get(
                        "shared_identity_domain", "mohanrajs.altostrat.com"
                    )
                ),
                "M365_SECRET_ID": str(
                    raw_config.get(
                        "m365_secret_id", "m365-connector-credentials"
                    )
                ),
                "M365_TENANT_ID": str(raw_config.get("m365_tenant_id", "")),
                "M365_CLIENT_ID": str(raw_config.get("m365_client_id", "")),
                "ENTRA_GROUP_FILTER": str(
                    raw_config.get("entra_group_filter", "")
                ),
                "ENTRA_TO_APP_GROUP_MAPPINGS": str(
                    raw_config.get("entra_to_app_group_mappings", "")
                ),
                "ENABLE_CLOUD_IDENTITY_SAML_SSO": (
                    "true"
                    if raw_config.get("enable_cloud_identity_saml_sso", True)
                    else "false"
                ),
                "SAML_SSO_PROFILE_DISPLAY_NAME": str(
                    raw_config.get(
                        "saml_sso_profile_display_name",
                        "Microsoft Entra ID SSO",
                    )
                ),
                "ENABLE_WORKFORCE_POOL_OIDC": (
                    "true"
                    if raw_config.get("enable_workforce_pool_oidc", False)
                    else "false"
                ),
                "WORKFORCE_POOL_ID": str(
                    raw_config.get("workforce_pool_id", "entra-id-shared-pool")
                ),
                "WORKFORCE_PROVIDER_ID": str(
                    raw_config.get(
                        "workforce_provider_id", "entra-id-oidc-provider"
                    )
                ),
            }
        )
    elif stack_type == "M365_CONNECTORS":
        prefix = str(raw_config.get("m365_collection_prefix", "m365"))
        file_vars.update(
            {
                "M365_COLLECTION_PREFIX": prefix,
                "GE_APP_ID": str(raw_config.get("ge_app_id", "")),
                "M365_SECRET_ID": str(
                    raw_config.get(
                        "m365_secret_id", "m365-connector-credentials"
                    )
                ),
                "M365_TENANT_ID": str(raw_config.get("m365_tenant_id", "")),
                "M365_CLIENT_ID": str(raw_config.get("m365_client_id", "")),
                "M365_CONNECTOR_MODE": str(
                    raw_config.get("m365_connector_mode", "FEDERATED")
                ),
                "ENABLE_M365_ACTIONS": (
                    "true"
                    if raw_config.get("enable_m365_actions", True)
                    else "false"
                ),
                "ENABLE_SHAREPOINT_CONNECTOR": (
                    "true"
                    if raw_config.get("enable_sharepoint_connector", True)
                    else "false"
                ),
                "M365_SHAREPOINT_COLLECTION_ID": f"{prefix}-sp",
                "M365_SHAREPOINT_INSTANCE_URI": str(
                    raw_config.get(
                        "m365_sharepoint_instance_uri",
                        "https://contoso.sharepoint.com",
                    )
                ),
                "ENABLE_ONEDRIVE_CONNECTOR": (
                    "true"
                    if raw_config.get("enable_onedrive_connector", True)
                    else "false"
                ),
                "M365_ONEDRIVE_COLLECTION_ID": f"{prefix}-od",
                "M365_ONEDRIVE_INSTANCE_URI": str(
                    raw_config.get(
                        "m365_onedrive_instance_uri",
                        "https://contoso-my.sharepoint.com",
                    )
                ),
                "ENABLE_OUTLOOK_CONNECTOR": (
                    "true"
                    if raw_config.get("enable_outlook_connector", True)
                    else "false"
                ),
                "M365_OUTLOOK_COLLECTION_ID": f"{prefix}-ol",
                "ENABLE_TEAMS_CONNECTOR": (
                    "true"
                    if raw_config.get("enable_teams_connector", True)
                    else "false"
                ),
                "M365_TEAMS_COLLECTION_ID": f"{prefix}-teams",
            }
        )

    return file_vars, ephemeral_env, secrets


class TerraformProvisioningService:
    """Executes Terraform stacks with workspace locks and plan gates."""

    def __init__(self, settings: config.Settings | None = None) -> None:
        self._settings = settings or config.get_settings()

    def _compute_workspace_and_prefix(
        self,
        stack_type: str,
        raw_config: dict[str, Any],
    ) -> tuple[str, str, str]:
        """Computes isolated workspace_key, state_prefix, and title."""
        loc = _slugify(str(raw_config.get("ge_location", "global")))
        if stack_type == "GE_APP":
            app_id = _slugify(str(raw_config.get("ge_app_id", "ge-app")))
            workspace = f"app-{loc}-{app_id}"
            prefix = f"gemini-enterprise/apps/{loc}/{app_id}"
            title = (
                f"GE App: {raw_config.get('ge_app_display_name') or app_id} "
                f"({loc})"
            )
            return workspace, prefix, title
        if stack_type == "IDENTITY_WIF":
            domain = _slugify(
                str(raw_config.get("primary_customer_domain", "corp"))
            )
            pool = _slugify(
                str(raw_config.get("workforce_pool_id", "identity-sync"))
            )
            workspace = f"id-{domain}-{pool}"
            prefix = f"gemini-enterprise/identity/{domain}/{pool}"
            title = (
                f"Identity & WIF: {raw_config.get('primary_customer_domain')} "
                f"({pool})"
            )
            return workspace, prefix, title
        prefix_slug = _slugify(
            str(raw_config.get("m365_collection_prefix", "m365"))
        )
        workspace = f"m365-{loc}-{prefix_slug}"
        prefix = f"gemini-enterprise/m365/{loc}/{prefix_slug}"
        app_target = raw_config.get("ge_app_id") or "standalone"
        title = f"M365 Connectors ({prefix_slug} -> {app_target})"
        return workspace, prefix, title

    def create_and_run_plan(
        self,
        session: orm.Session,
        stack_type: str,
        raw_config: dict[str, Any],
        initiated_by: str,
    ) -> db_models.ProvisioningJobRecord:
        """Creates a provisioning job, locks workspace, and runs plan/apply."""
        workspace_key, state_prefix, title = self._compute_workspace_and_prefix(
            stack_type, raw_config
        )
        job_id = f"prov-{uuid.uuid4().hex[:10]}"
        acquire_workspace_lock(workspace_key, job_id)

        state_bucket = str(raw_config.get("tf_state_bucket") or "").strip()
        backend_type = "GCS_REMOTE" if state_bucket else "LOCAL_WORKSPACE"
        exec_mode = (
            str(raw_config.get("execution_mode") or "PLAN_AND_WAIT")
            .strip()
            .upper()
        )

        record = db_models.ProvisioningJobRecord(
            job_id=job_id,
            stack_type=stack_type,
            title=title,
            workspace_key=workspace_key,
            state_backend_type=backend_type,
            state_bucket=state_bucket,
            state_prefix=state_prefix,
            execution_mode=exec_mode,
            status="PLANNING",
            initiated_by=initiated_by,
            sanitized_config=sanitize_config_dict(raw_config),
            log_lines=[],
            outputs={},
        )
        session.add(record)
        session.commit()

        try:
            self._execute_phase(
                session=session,
                record=record,
                raw_config=raw_config,
                phase="PLAN",
            )
            if exec_mode == "APPLY" and record.status != "FAILED":
                self._execute_phase(
                    session=session,
                    record=record,
                    raw_config=raw_config,
                    phase="APPLY",
                )
        finally:
            if record.status != "PENDING_APPROVAL":
                release_workspace_lock(workspace_key, job_id)
        return record

    def approve_and_apply(
        self,
        session: orm.Session,
        job_id: str,
        approver_email: str,
        notes: str = "",
    ) -> db_models.ProvisioningJobRecord:
        """Approves a PENDING_APPROVAL job and executes the Terraform apply."""
        record = (
            session.query(db_models.ProvisioningJobRecord)
            .filter_by(job_id=job_id)
            .one_or_none()
        )
        if record is None:
            raise KeyError(f"Provisioning job '{job_id}' not found.")
        if record.status != "PENDING_APPROVAL":
            raise ValueError(
                f"Job '{job_id}' is in status '{record.status}', "
                "expected 'PENDING_APPROVAL'."
            )

        acquire_workspace_lock(record.workspace_key, record.job_id)
        try:
            record.approved_by = approver_email
            logs = list(record.log_lines or [])
            logs.append(
                f"[APPROVAL] Plan approved by {approver_email}"
                + (f" ({notes})" if notes else "")
            )
            record.log_lines = logs
            record.status = "APPLYING"
            session.commit()

            self._execute_phase(
                session=session,
                record=record,
                raw_config=dict(record.sanitized_config or {}),
                phase="APPLY",
            )
        finally:
            release_workspace_lock(record.workspace_key, record.job_id)
        return record

    def reject_job(
        self,
        session: orm.Session,
        job_id: str,
        reviewer_email: str,
        notes: str = "",
    ) -> db_models.ProvisioningJobRecord:
        """Rejects a PENDING_APPROVAL job and releases its workspace lock."""
        record = (
            session.query(db_models.ProvisioningJobRecord)
            .filter_by(job_id=job_id)
            .one_or_none()
        )
        if record is None:
            raise KeyError(f"Provisioning job '{job_id}' not found.")
        release_workspace_lock(record.workspace_key, record.job_id)
        record.status = "REJECTED"
        record.approved_by = reviewer_email
        logs = list(record.log_lines or [])
        logs.append(
            f"[REJECTED] Plan rejected by {reviewer_email}"
            + (f": {notes}" if notes else "")
        )
        record.log_lines = logs
        record.completed_at = _utc_now()
        session.commit()
        return record

    def _execute_phase(
        self,
        session: orm.Session,
        record: db_models.ProvisioningJobRecord,
        raw_config: dict[str, Any],
        phase: str,
    ) -> None:
        """Executes the PLAN (dry-run) or APPLY phase and records logs."""
        file_vars, ephemeral_env, secrets = _build_env_and_secrets(
            stack_type=record.stack_type,
            raw_config=raw_config,
            workspace_key=record.workspace_key,
            state_prefix=record.state_prefix,
        )
        logs = list(record.log_lines or [])
        logs.append(
            f"[{phase}] Workspace='{record.workspace_key}' "
            f"Backend='{record.state_backend_type}' "
            f"Prefix='{record.state_prefix}'"
        )
        logs.append(
            "[SECURITY] Sensitive credentials injected via ephemeral "
            "TF_VAR_* environment (zero plaintext secret files on disk)."
        )

        script_map = {
            "GE_APP": INFRA_ROOT / "deploy.sh",
            "IDENTITY_WIF": INFRA_ROOT / "deploy_identity.sh",
            "M365_CONNECTORS": INFRA_ROOT / "deploy_m365.sh",
        }
        script_path = script_map[record.stack_type]

        with tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".env",
            prefix=f"{record.job_id}-",
            delete=False,
            encoding="utf-8",
        ) as tmp_env:
            tmp_path = pathlib.Path(tmp_env.name)
            for k, v in sorted(file_vars.items()):
                escaped = str(v).replace('"', '\\"')
                tmp_env.write(f'{k}="{escaped}"\n')

        try:
            if phase == "PLAN":
                cmd_lines = self._run_script_or_preview(
                    script_path=script_path,
                    tmp_env_path=tmp_path,
                    ephemeral_env=ephemeral_env,
                    secrets=secrets,
                    dry_run=True,
                    record=record,
                    file_vars=file_vars,
                )
                logs.extend(cmd_lines)
                record.plan_summary = "\n".join(cmd_lines[-14:])
                if record.execution_mode == "DRY_RUN":
                    record.status = "SUCCEEDED"
                    record.outputs = self._build_outputs(
                        record.stack_type, file_vars, dry_run=True
                    )
                    record.completed_at = _utc_now()
                elif record.execution_mode == "PLAN_AND_WAIT":
                    logs.append(
                        "[GATE] Terraform Plan & REST Dry-Run complete. "
                        "Awaiting Admin Approval before Apply."
                    )
                    record.status = "PENDING_APPROVAL"
                else:
                    record.status = "APPLYING"
            else:
                apply_lines = self._run_script_or_preview(
                    script_path=script_path,
                    tmp_env_path=tmp_path,
                    ephemeral_env=ephemeral_env,
                    secrets=secrets,
                    dry_run=False,
                    record=record,
                    file_vars=file_vars,
                )
                logs.extend(apply_lines)
                record.outputs = self._build_outputs(
                    record.stack_type, file_vars, dry_run=False
                )
                record.status = "SUCCEEDED"
                record.completed_at = _utc_now()
                self._post_apply_catalog_sync(session, record, file_vars, logs)
        except Exception as exc:  # pylint: disable=broad-except
            err_msg = redact_sensitive_text(str(exc), secrets)
            logs.append(f"[ERROR] {err_msg}")
            record.error_message = err_msg
            record.status = "FAILED"
            record.completed_at = _utc_now()
        finally:
            tmp_path.unlink(missing_ok=True)
            record.log_lines = logs
            record.updated_at = _utc_now()
            session.commit()

    def _run_script_or_preview(
        self,
        script_path: pathlib.Path,
        tmp_env_path: pathlib.Path,
        ephemeral_env: dict[str, str],
        secrets: list[str],
        dry_run: bool,
        record: db_models.ProvisioningJobRecord,
        file_vars: dict[str, str],
    ) -> list[str]:
        """Runs the infra/deploy*.sh script or deterministic plan preview."""
        simulate = (
            self._settings.use_mock_data
            or os.getenv("PROVISIONING_SIMULATE", "true").lower() == "true"
        )
        if not simulate and script_path.is_file():
            cmd = [str(script_path), "--config", str(tmp_env_path)]
            if dry_run:
                cmd.append("--dry-run")
            env = {**os.environ, **ephemeral_env}
            proc = subprocess.run(
                cmd,
                cwd=str(INFRA_ROOT),
                env=env,
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
            )
            combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
            lines = [
                redact_sensitive_text(line.rstrip(), secrets)
                for line in combined.splitlines()
                if line.strip()
            ]
            if proc.returncode != 0:
                raise RuntimeError(
                    f"Script exited with code {proc.returncode}: "
                    + (lines[-1] if lines else "unknown error")
                )
            return lines

        mode_label = "PLAN (DRY-RUN)" if dry_run else "APPLY"
        stack_dir = {
            "GE_APP": "infra/stacks/02-ge-app-instance",
            "IDENTITY_WIF": "infra/stacks/01-identity-foundation",
            "M365_CONNECTORS": "infra/stacks/03-m365-connectors",
        }[record.stack_type]

        lines = [
            f"[TERRAFORM] terraform -chdir={stack_dir} init -input=false",
            (
                f"[TERRAFORM] terraform -chdir={stack_dir} workspace "
                f"select -or-create {record.workspace_key}"
            ),
            f"[TERRAFORM] terraform -chdir={stack_dir} validate",
        ]
        if dry_run:
            lines.append(
                f"[TERRAFORM] terraform -chdir={stack_dir} plan -out=tfplan "
                f"(project={file_vars['GCP_PROJECT_ID']}, "
                f"location={file_vars['GE_LOCATION']})"
            )
        else:
            lines.append(
                f"[TERRAFORM] terraform -chdir={stack_dir} apply "
                "-auto-approve tfplan"
            )

        if record.stack_type == "GE_APP":
            app_id = file_vars.get("GE_APP_ID", "")
            ds_id = file_vars.get("GE_DATA_STORE_ID", "")
            storage = file_vars.get("GE_BACKING_STORAGE_TYPE", "GCS")
            grp = file_vars.get("GE_APP_ACCESS_GROUP") or f"{app_id}-users"
            lines.extend(
                [
                    (
                        f"[{mode_label}] Upsert Discovery Engine Data Store "
                        f"'{ds_id}' ({storage})"
                    ),
                    (
                        f"[{mode_label}] Upsert Gemini Enterprise Engine "
                        f"'{app_id}' "
                        f"(tier={file_vars.get('GE_SEARCH_TIER')}, "
                        f"idp={file_vars.get('GE_IDENTITY_PROVIDER_TYPE')})"
                    ),
                    (
                        f"[{mode_label}] Bind Cloud Identity Access Group "
                        f"'{grp}'"
                    ),
                ]
            )
        elif record.stack_type == "IDENTITY_WIF":
            dom = file_vars.get("PRIMARY_CUSTOMER_DOMAIN", "")
            prof = file_vars.get("SAML_SSO_PROFILE_DISPLAY_NAME", "")
            lines.extend(
                [
                    (
                        f"[{mode_label}] Sync Microsoft Entra ID groups to "
                        f"Cloud Identity ({dom})"
                    ),
                    (
                        f"[{mode_label}] Configure Location ACL idpType=GSUITE "
                        f"& Inbound SAML SSO Profile ('{prof}')"
                    ),
                ]
            )
        else:
            prefix = file_vars.get("M365_COLLECTION_PREFIX", "m365")
            enabled: list[str] = []
            if file_vars.get("ENABLE_SHAREPOINT_CONNECTOR") == "true":
                enabled.append(f"{prefix}-sp (SharePoint)")
            if file_vars.get("ENABLE_OUTLOOK_CONNECTOR") == "true":
                enabled.append(f"{prefix}-ol (Outlook)")
            if file_vars.get("ENABLE_TEAMS_CONNECTOR") == "true":
                enabled.append(f"{prefix}-teams (Teams)")
            if file_vars.get("ENABLE_ONEDRIVE_CONNECTOR") == "true":
                enabled.append(f"{prefix}-od (OneDrive)")
            lines.extend(
                [
                    (
                        f"[{mode_label}] Upsert Secret Manager secret "
                        f"'{file_vars.get('M365_SECRET_ID')}'"
                    ),
                    (
                        f"[{mode_label}] Call :setUpDataConnector for "
                        + ", ".join(enabled)
                    ),
                ]
            )
        return [redact_sensitive_text(item, secrets) for item in lines]

    def _build_outputs(
        self,
        stack_type: str,
        file_vars: dict[str, str],
        dry_run: bool,
    ) -> dict[str, Any]:
        """Builds structured Terraform / REST outputs for the completed job."""
        proj = file_vars.get("GCP_PROJECT_ID", "mohandemo")
        loc = file_vars.get("GE_LOCATION", "global")
        if stack_type == "GE_APP":
            app_id = file_vars.get("GE_APP_ID", "")
            ds_id = file_vars.get("GE_DATA_STORE_ID", f"{app_id}-ds")
            return {
                "engine_id": app_id,
                "data_store_id": ds_id,
                "location": loc,
                "engine_resource_name": (
                    f"projects/{proj}/locations/{loc}/collections/"
                    f"default_collection/engines/{app_id}"
                ),
                "console_url": (
                    f"https://console.cloud.google.com/gen-app-builder/"
                    f"locations/{loc}/engines/{app_id}?project={proj}"
                ),
                "dry_run": dry_run,
            }
        if stack_type == "IDENTITY_WIF":
            return {
                "primary_customer_domain": file_vars.get(
                    "PRIMARY_CUSTOMER_DOMAIN", ""
                ),
                "saml_sso_enabled": (
                    file_vars.get("ENABLE_CLOUD_IDENTITY_SAML_SSO") == "true"
                ),
                "workforce_pool_id": file_vars.get("WORKFORCE_POOL_ID", ""),
                "dry_run": dry_run,
            }
        prefix = file_vars.get("M365_COLLECTION_PREFIX", "m365")
        stores: list[str] = []
        if file_vars.get("ENABLE_SHAREPOINT_CONNECTOR") == "true":
            stores.append(f"{prefix}-sp")
        if file_vars.get("ENABLE_OUTLOOK_CONNECTOR") == "true":
            stores.append(f"{prefix}-ol")
        if file_vars.get("ENABLE_TEAMS_CONNECTOR") == "true":
            stores.append(f"{prefix}-teams")
        if file_vars.get("ENABLE_ONEDRIVE_CONNECTOR") == "true":
            stores.append(f"{prefix}-od")
        return {
            "m365_collection_prefix": prefix,
            "provisioned_data_store_ids": stores,
            "bound_engine_id": file_vars.get("GE_APP_ID", ""),
            "dry_run": dry_run,
        }

    def _post_apply_catalog_sync(
        self,
        session: orm.Session,
        record: db_models.ProvisioningJobRecord,
        file_vars: dict[str, str],
        logs: list[str],
    ) -> None:
        """Upserts provisioned GE App / M365 Data Stores into the Catalog DB."""
        loc = file_vars.get("GE_LOCATION", "global")
        if record.stack_type == "GE_APP":
            app_id = file_vars.get("GE_APP_ID", "").strip()
            ds_id = file_vars.get("GE_DATA_STORE_ID", f"{app_id}-ds").strip()
            display_name = file_vars.get("GE_APP_DISPLAY_NAME", app_id).strip()
            existing = (
                session.query(db_models.GEApplicationRecord)
                .filter_by(engine_id=app_id)
                .one_or_none()
            )
            launch_url = (
                f"https://vertexaisearch.cloud.google.com/home/cid/{app_id}"
            )
            ds_list = [ds_id] if ds_id else []
            if file_vars.get("GE_ENABLE_COMMON_CONNECTORS") == "true":
                ds_list.extend(
                    ["m365-sp", "m365-ol", "m365-teams", "m365-od"]
                )
            if existing is None and app_id:
                session.add(
                    db_models.GEApplicationRecord(
                        engine_id=app_id,
                        display_name=display_name,
                        description=(
                            f"Provisioned via Admin Studio in {loc} "
                            f"(Workspace: {record.workspace_key})."
                        ),
                        category="Enterprise Search",
                        department="Enterprise",
                        tags=["terraform", loc, "gemini-enterprise"],
                        icon_name="Sparkles",
                        launch_url=launch_url,
                        default_launch_url=launch_url,
                        location=loc,
                        solution_type=file_vars.get(
                            "GE_SOLUTION_TYPE", "SOLUTION_TYPE_SEARCH"
                        ),
                        industry_vertical=file_vars.get(
                            "GE_INDUSTRY_VERTICAL", "GENERIC"
                        ),
                        app_type="APP_TYPE_INTRANET",
                        iam_principals=["user:admin@mohanrajs.altostrat.com"],
                        data_store_ids=sorted(set(ds_list)),
                        allowed_roles=["*"],
                        featured=True,
                    )
                )
            elif existing is not None:
                cur_ids = list(existing.data_store_ids or [])
                merged = sorted(set(cur_ids + ds_list))
                existing.data_store_ids = merged
            logs.append(
                f"[SYNC] Registered GE Engine '{app_id}' and data stores "
                f"{sorted(set(ds_list))} in AppHub Catalog."
            )
        elif record.stack_type == "M365_CONNECTORS":
            target_app = file_vars.get("GE_APP_ID", "").strip()
            new_stores = record.outputs.get("provisioned_data_store_ids", [])
            if target_app and new_stores:
                existing = (
                    session.query(db_models.GEApplicationRecord)
                    .filter_by(engine_id=target_app)
                    .one_or_none()
                )
                if existing is not None:
                    cur_ids = list(existing.data_store_ids or [])
                    merged = sorted(set(cur_ids + list(new_stores)))
                    existing.data_store_ids = merged
                    logs.append(
                        f"[SYNC] Attached M365 data stores {new_stores} to "
                        f"GE Engine '{target_app}'."
                    )
