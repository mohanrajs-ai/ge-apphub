#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${PROJECT_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/configure_ge_app.sh
source "${PROJECT_ROOT}/scripts/configure_ge_app.sh"
# shellcheck source=scripts/register_agents.sh
source "${PROJECT_ROOT}/scripts/register_agents.sh"

test_payload_templates_and_ge_app_config() {
  assert_file_exists "${PROJECT_ROOT}/payloads/app_config.json.tmpl" "payloads/app_config.json.tmpl exists"
  assert_file_exists "${PROJECT_ROOT}/payloads/acl_config.json.tmpl" "payloads/acl_config.json.tmpl exists"

  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export DRY_RUN="false"

  local acl_json assistant_json
  acl_json="$(render_acl_payload)"
  assert_contains "${acl_json}" "\"idpType\": \"GSUITE\"" "Rendered ACL payload contains idpType"

  export GE_IDENTITY_PROVIDER_TYPE="THIRD_PARTY"
  export GE_WORKFORCE_IDENTITY_POOL="locations/global/workforcePools/corp-pool"
  local wf_acl_json
  wf_acl_json="$(render_acl_payload)"
  assert_contains "${wf_acl_json}" "corp-pool" "Rendered Workforce ACL payload contains pool name"
  export GE_IDENTITY_PROVIDER_TYPE="GSUITE"

  assistant_json="$(render_assistant_payload)"
  assert_contains "${assistant_json}" "${GE_ASSISTANT_SYSTEM_INSTRUCTION}" "Rendered Assistant payload contains system instruction"

  local common_ds_json eng_payload_json widget_payload_json
  common_ds_json="$(resolve_common_connector_datastore_ids)"
  assert_contains "${common_ds_json}" "m365-od_file" "resolve_common_connector_datastore_ids includes M365 OneDrive entity data store"
  eng_payload_json="$(render_engine_payload)"
  assert_contains "${eng_payload_json}" "${GE_DATA_STORE_ID}" "Rendered Engine payload includes primary app data store"
  assert_contains "${eng_payload_json}" "m365-od_file" "Rendered Engine payload includes common M365 connector data stores"
  assert_contains "${eng_payload_json}" "\"enablePrivateKnowledgeGraph\": true" "Rendered Engine payload enables Private Knowledge Graph"
  assert_contains "${eng_payload_json}" "\"enableKnowledgeCatalog\": true" "Rendered Engine payload enables Knowledge Catalog"
  assert_contains "${eng_payload_json}" "\"enableModelArmor\": true" "Rendered Engine payload enables Model Armor"
  assert_contains "${eng_payload_json}" "\"enableObservability\": true" "Rendered Engine payload enables Observability"
  assert_contains "${eng_payload_json}" "\"deep-research\": \"FEATURE_STATE_ON\"" "Rendered Engine payload enables Full Feature Matrix"
  assert_contains "${eng_payload_json}" "\"agent-sharing\": \"FEATURE_STATE_OFF\"" "Rendered Engine payload disables Agent Sharing"
  assert_contains "${eng_payload_json}" "\"allowAgentSharing\": false" "Rendered Engine sharingConfig disables Agent Sharing"
  assert_contains "${eng_payload_json}" "\"skills\": \"FEATURE_STATE_ON\"" "Rendered Engine payload enables Skills"
  assert_contains "${eng_payload_json}" "\"skill-sharing-admin-approval\": \"FEATURE_STATE_ON\"" "Rendered Engine payload enables Skill Sharing with Admin Approval"
  assert_contains "${eng_payload_json}" "\"skillSharingPolicy\": \"ADMIN_APPROVAL_REQUIRED\"" "Rendered Engine sharingConfig enforces ADMIN_APPROVAL_REQUIRED for Skills"
  assert_contains "${eng_payload_json}" "\"requireAdminApprovalForSkillSharing\": true" "Rendered Engine sharingConfig requires Admin Approval for Skill Sharing"
  assert_contains "${eng_payload_json}" "\"projects\": \"FEATURE_STATE_ON\"" "Rendered Engine payload enables Projects"
  assert_contains "${eng_payload_json}" "\"enableProjects\": true" "Rendered Engine sharingConfig enables Projects"

  widget_payload_json="$(render_widget_config_payload)"
  assert_contains "${widget_payload_json}" "\"enableAutocomplete\": true" "Rendered Widget payload enables Autocomplete"
  assert_contains "${widget_payload_json}" "\"enableQualityFeedback\": true" "Rendered Widget payload enables Feedback Config"
  assert_contains "${widget_payload_json}" "\"enableUserEventCollection\": true" "Rendered Widget payload enables User Event Collection"
  assert_contains "${widget_payload_json}" "\"allowAgentSharing\": false" "Rendered Widget payload disables Agent Sharing"
  assert_contains "${widget_payload_json}" "\"enableSkills\": true" "Rendered Widget payload enables Skills"
  assert_contains "${widget_payload_json}" "\"requireAdminApprovalForSkillSharing\": true" "Rendered Widget payload requires Admin Approval for Skill Sharing"
  assert_contains "${widget_payload_json}" "\"enableProjects\": true" "Rendered Widget payload enables Projects"
  assert_contains "${widget_payload_json}" "\"collectionComponents\"" "Rendered Widget payload includes Admin-Configured Connector Display Names"

  local group_json member_json
  group_json="$(render_cloud_identity_group_payload "customers/C01234567" "${GE_APP_ACCESS_GROUP}" "${GE_APP_DISPLAY_NAME} Users" "Group for ${GE_APP_ID}")"
  assert_contains "${group_json}" "\"parent\": \"customers/C01234567\"" "Rendered Cloud Identity group payload contains customer parent"
  assert_contains "${group_json}" "\"id\": \"${GE_APP_ACCESS_GROUP}\"" "Rendered Cloud Identity group payload contains groupKey.id"

  member_json="$(render_cloud_identity_membership_payload "admin@example.com")"
  assert_contains "${member_json}" "\"id\": \"admin@example.com\"" "Rendered Cloud Identity membership payload contains member email"
  assert_contains "${member_json}" "\"name\": \"MEMBER\"" "Rendered Cloud Identity membership payload contains MEMBER role"

  local eng_iam_json
  eng_iam_json="$(render_engine_iam_policy_payload "${GE_APP_ACCESS_GROUP}" "etag123")"
  assert_contains "${eng_iam_json}" "\"group:${GE_APP_ACCESS_GROUP}\"" "Rendered Engine IAM policy binds group:<app_access_group>"
  assert_contains "${eng_iam_json}" "roles/discoveryengine.user" "Rendered Engine IAM policy includes roles/discoveryengine.user"
  assert_contains "${eng_iam_json}" "roles/discoveryengine.viewer" "Rendered Engine IAM policy includes roles/discoveryengine.viewer"

  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_POST_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  configure_gemini_enterprise_app "false" >/dev/null

  local calls
  calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${calls}" "aclConfig" "Configures project/location aclConfig endpoint via curl"
  assert_contains "${calls}" "assistants/default_assistant" "Configures Gemini Enterprise default_assistant via curl"
  assert_contains "${calls}" "cloudidentity.googleapis.com/v1/groups" "Provisions per-app Cloud Identity group during configure_gemini_enterprise_app"
  assert_contains "${calls}" ":getIamPolicy" "Checks Project and Engine IAM policies"
  assert_contains "${calls}" "engines/${GE_APP_ID}:setIamPolicy" "Sets exclusive Engine-level IAM policy for app group"

  # Exercise existing group + membership sync and project-level broad IAM revocation branch
  export MOCK_CURL_BODY="{\"name\":\"groups/mock123\",\"etag\":\"etag1\",\"groups\":[{\"name\":\"groups/mock123\",\"groupKey\":{\"id\":\"${GE_APP_ACCESS_GROUP}\"}}],\"bindings\":[{\"role\":\"roles/discoveryengine.user\",\"members\":[\"user:extra@example.com\"]}]}"
  : > "${MOCK_CALL_LOG}"
  configure_gemini_enterprise_app "false" >/dev/null
  local revoke_calls
  revoke_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${revoke_calls}" "groups/mock123/memberships" "Syncs group memberships when group resource name is resolved"
  assert_contains "${revoke_calls}" "projects/${GCP_PROJECT_ID}:setIamPolicy" "Revokes broad project-level Discovery Engine user/viewer bindings"
  unset MOCK_CURL_BODY

  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  configure_gemini_enterprise_app "true" >/dev/null

  local curl_only_calls
  curl_only_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${curl_only_calls}" "dataStores?dataStoreId=${GE_DATA_STORE_ID}" "Fallback curl-only creates Data Store via POST"
  assert_contains "${curl_only_calls}" "engines?engineId=${GE_APP_ID}" "Fallback curl-only creates Gemini Enterprise Engine via POST"

  teardown_mock_env
}

test_agent_registration_and_deregistration() {
  assert_file_exists "${PROJECT_ROOT}/payloads/agent_registration.json.tmpl" "payloads/agent_registration.json.tmpl exists"

  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export DRY_RUN="false"

  local agent_payload
  agent_payload="$(render_agent_payload)"
  assert_contains "${agent_payload}" "${AGENT_DISPLAY_NAME}" "Agent payload includes displayName"
  assert_contains "${agent_payload}" "${AGENT_REASONING_ENGINE}" "Agent payload includes reasoningEngine"

  # 1. Enabled registration (new agent -> 404 on GET, 200 on POST)
  export ENABLE_AGENT_REGISTRATION="true"
  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  register_gemini_enterprise_agents >/dev/null
  local reg_calls
  reg_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${reg_calls}" "agents" "Calls Gemini Enterprise agents endpoint"
  assert_contains "${reg_calls}" "-X POST" "Creates new agent registration via POST"

  # 2. Disabled registration skips API calls
  export ENABLE_AGENT_REGISTRATION="false"
  : > "${MOCK_CALL_LOG}"
  register_gemini_enterprise_agents >/dev/null
  deregister_gemini_enterprise_agents >/dev/null
  local skipped_calls
  skipped_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_eq "" "${skipped_calls}" "Skips curl calls when ENABLE_AGENT_REGISTRATION=false"

  # 3. Deregister agent (--destroy support)
  export ENABLE_AGENT_REGISTRATION="true"
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_DELETE_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  deregister_gemini_enterprise_agents >/dev/null
  local del_calls
  del_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${del_calls}" "-X DELETE" "Deregisters agent via DELETE"

  teardown_mock_env
}

run_test_suite "Gemini Enterprise curl Provisioning Modules" \
  test_payload_templates_and_ge_app_config \
  test_agent_registration_and_deregistration
