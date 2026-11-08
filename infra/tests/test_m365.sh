#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=deploy_m365.sh
source "${PROJECT_ROOT}/deploy_m365.sh"

TF_M365_DIR="${PROJECT_ROOT}/terraform-m365"

test_m365_terraform_files() {
  assert_file_exists "${TF_M365_DIR}/versions.tf" "terraform-m365/versions.tf exists"
  assert_file_exists "${TF_M365_DIR}/variables.tf" "terraform-m365/variables.tf exists"
  assert_file_exists "${TF_M365_DIR}/m365_connectors.tf" "terraform-m365/m365_connectors.tf exists"
  assert_file_exists "${TF_M365_DIR}/outputs.tf" "terraform-m365/outputs.tf exists"

  local connectors_tf vars_tf outputs_tf
  connectors_tf="$(cat "${TF_M365_DIR}/m365_connectors.tf")"
  vars_tf="$(cat "${TF_M365_DIR}/variables.tf")"
  outputs_tf="$(cat "${TF_M365_DIR}/outputs.tf")"

  assert_contains "${connectors_tf}" "resource \"google_discovery_engine_data_connector\" \"sharepoint\"" "Defines SharePoint connector resource"
  assert_contains "${connectors_tf}" "resource \"google_discovery_engine_data_connector\" \"onedrive\"" "Defines OneDrive connector resource"
  assert_contains "${connectors_tf}" "resource \"google_discovery_engine_data_connector\" \"outlook\"" "Defines Outlook connector resource"
  assert_contains "${connectors_tf}" "resource \"google_discovery_engine_data_connector\" \"teams\"" "Defines Teams connector resource"
  assert_contains "${connectors_tf}" "dynamic \"action_config\"" "Defines dynamic action_config block for write actions"
  assert_contains "${connectors_tf}" "dynamic \"bap_config\"" "Defines dynamic bap_config block for enabled_actions"

  assert_contains "${vars_tf}" "variable \"m365_tenant_id\"" "Declares m365_tenant_id variable"
  assert_contains "${vars_tf}" "variable \"m365_client_id\"" "Declares m365_client_id variable"
  assert_contains "${vars_tf}" "variable \"m365_client_secret\"" "Declares m365_client_secret variable"
  assert_contains "${vars_tf}" "variable \"m365_secret_id\"" "Declares m365_secret_id variable"
  assert_contains "${vars_tf}" "variable \"enable_m365_actions\"" "Declares enable_m365_actions variable"
  assert_contains "${connectors_tf}" "resource \"google_project_service\" \"secretmanager\"" "Enables secretmanager.googleapis.com API"
  assert_contains "${connectors_tf}" "resource \"google_secret_manager_secret\" \"m365_credentials\"" "Creates Secret Manager secret for M365 JSON credentials"
  assert_contains "${connectors_tf}" "resource \"google_secret_manager_secret_version\" \"m365_credentials_initial\"" "Seeds initial JSON secret version"
  assert_contains "${connectors_tf}" "data \"google_secret_manager_secret_version\" \"m365_credentials_latest\"" "Reads latest JSON secret version from Secret Manager"
  assert_contains "${connectors_tf}" "local.m365_secret_json" "Resolves tenant_id, client_id, and client_secret from JSON secret"
  assert_contains "${outputs_tf}" "output \"sharepoint_connector_name\"" "Exports sharepoint_connector_name output"
  assert_contains "${outputs_tf}" "output \"m365_secret_name\"" "Exports m365_secret_name output"
}

test_m365_scripts_and_cli_modes() {
  assert_file_exists "${PROJECT_ROOT}/configs/m365.env.example" "configs/m365.env.example exists"
  assert_file_exists "${PROJECT_ROOT}/payloads/m365_connector.json.tmpl" "payloads/m365_connector.json.tmpl exists"

  setup_mock_env
  local cfg="${PROJECT_ROOT}/configs/m365.env.example"
  unset M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET
  load_m365_config "${cfg}" >/dev/null
  assert_eq "m365-connector-credentials" "${M365_SECRET_ID:-}" "Default M365_SECRET_ID loaded"
  assert_eq "m365-connector-credentials" "${TF_VAR_m365_secret_id:-}" "Exports TF_VAR_m365_secret_id"

  # Validate fails when M365 secret environment variables are unset
  local val_rc=0
  validate_m365_config >/dev/null 2>&1 || val_rc=$?
  assert_eq "1" "${val_rc}" "validate_m365_config fails when M365 secret environment variables are missing"

  # Export M365 secret environment variables and verify load + validation succeed
  export M365_TENANT_ID="env-tenant-123"
  export M365_CLIENT_ID="env-client-456"
  export M365_CLIENT_SECRET="env-secret-789"
  load_m365_config "${cfg}" >/dev/null
  validate_m365_config >/dev/null
  assert_eq "env-tenant-123" "${TF_VAR_m365_tenant_id}" "Exports TF_VAR_m365_tenant_id from environment variable"
  assert_eq "env-client-456" "${TF_VAR_m365_client_id}" "Exports TF_VAR_m365_client_id from environment variable"
  assert_eq "env-secret-789" "${TF_VAR_m365_client_secret}" "Exports TF_VAR_m365_client_secret from environment variable"

  # Test Secret Manager auto-creation and JSON resolution from environment variables
  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  ensure_and_load_m365_secret_credentials >/dev/null
  local sm_calls
  sm_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${sm_calls}" "secretmanager.googleapis.com/v1/projects/customer-ge-prod-001/secrets" "Calls Secret Manager API to ensure M365 secret exists"
  assert_contains "${sm_calls}" ":addVersion" "Seeds initial JSON secret version when missing"

  # Test fallback loading existing JSON secret from Secret Manager versions/latest:access when env vars are unset
  unset M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET
  export MOCK_CURL_GET_STATUS="200"
  local b64_json
  b64_json="$(printf '%s' '{"tenant_id":"sm-tenant-999","client_id":"sm-client-888","client_secret":"sm-secret-777"}' | base64 | tr -d '\n')"
  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"}}"
  ensure_and_load_m365_secret_credentials >/dev/null
  unset MOCK_CURL_BODY
  assert_eq "sm-tenant-999" "${M365_TENANT_ID}" "Loads M365_TENANT_ID from Secret Manager JSON fallback"
  assert_eq "sm-client-888" "${M365_CLIENT_ID}" "Loads M365_CLIENT_ID from Secret Manager JSON fallback"
  assert_eq "sm-secret-777" "${M365_CLIENT_SECRET}" "Loads M365_CLIENT_SECRET from Secret Manager JSON fallback"

  local sp_payload
  sp_payload="$(render_m365_connector_payload "sharepoint" "https://contoso.sharepoint.com" "file,page" "DATA_INGESTION" "upload_document,add_page")"
  assert_contains "${sp_payload}" "\"dataSource\": \"sharepoint\"" "Rendered SharePoint payload contains dataSource"
  assert_contains "${sp_payload}" "\"entityName\": \"file\"" "Rendered SharePoint payload contains file entity"
  assert_contains "${sp_payload}" "\"entityName\": \"page\"" "Rendered SharePoint payload contains page entity"
  assert_contains "${sp_payload}" "\"createBapConnection\": true" "Rendered payload includes createBapConnection when ENABLE_M365_ACTIONS=true"
  assert_contains "${sp_payload}" "\"upload_document\"" "Rendered payload includes enabledActions"

  # Test all 4 connectors enabled in curl-only mode
  local tmp_cfg
  tmp_cfg="$(mktemp)"
  cp "${cfg}" "${tmp_cfg}"
  cat >> "${tmp_cfg}" <<'EOF'
ENABLE_SHAREPOINT_CONNECTOR="true"
ENABLE_ONEDRIVE_CONNECTOR="true"
ENABLE_OUTLOOK_CONNECTOR="true"
ENABLE_TEAMS_CONNECTOR="true"
GE_APP_ID="finance-app-01"
TF_STATE_BUCKET="m365-tf-state-bucket"
EOF

  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="200"
  load_m365_config "${tmp_cfg}" >/dev/null
  : > "${MOCK_CALL_LOG}"
  configure_m365_connectors "true" >/dev/null
  local curl_calls
  curl_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${curl_calls}" "setUpDataConnectorV2?collectionId=m365-sp" "Provisions SharePoint connector via setUpDataConnectorV2"
  assert_contains "${curl_calls}" "setUpDataConnectorV2?collectionId=m365-od" "Provisions OneDrive connector via setUpDataConnectorV2"
  assert_contains "${curl_calls}" "setUpDataConnectorV2?collectionId=m365-ol" "Provisions Outlook connector via setUpDataConnectorV2"
  assert_contains "${curl_calls}" "setUpDataConnectorV2?collectionId=m365-teams" "Provisions Teams connector via setUpDataConnectorV2"

  # Full mode, curl-only, dry-run, terraform-only, verify-only, destroy, help
  export MOCK_CURL_GET_STATUS="200"
  deploy_m365_main --config "${tmp_cfg}" --curl-only >/dev/null
  deploy_m365_main --config "${tmp_cfg}" >/dev/null
  deploy_m365_main --config "${tmp_cfg}" --dry-run >/dev/null
  deploy_m365_main --config "${tmp_cfg}" --terraform-only >/dev/null
  deploy_m365_main --config "${tmp_cfg}" --verify-only >/dev/null
  deploy_m365_main --config "${tmp_cfg}" --destroy >/dev/null
  deploy_m365_main --help >/dev/null

  rm -f "${tmp_cfg}"
  teardown_mock_env
}

run_test_suite "Microsoft 365 (M365) Data Connectors Suite" \
  test_m365_terraform_files \
  test_m365_scripts_and_cli_modes
