#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=deploy_servicenow.sh
source "${PROJECT_ROOT}/deploy_servicenow.sh"

TF_SN_DIR="${PROJECT_ROOT}/terraform-servicenow"

test_servicenow_terraform_files() {
  assert_file_exists "${TF_SN_DIR}/versions.tf" "terraform-servicenow/versions.tf exists"
  assert_file_exists "${TF_SN_DIR}/variables.tf" "terraform-servicenow/variables.tf exists"
  assert_file_exists "${TF_SN_DIR}/servicenow_connector.tf" "terraform-servicenow/servicenow_connector.tf exists"
  assert_file_exists "${TF_SN_DIR}/outputs.tf" "terraform-servicenow/outputs.tf exists"
  assert_file_exists "${PROJECT_ROOT}/payloads/servicenow_connector.json.tmpl" "payloads/servicenow_connector.json.tmpl exists"

  local connector_tf vars_tf outputs_tf
  connector_tf="$(cat "${TF_SN_DIR}/servicenow_connector.tf")"
  vars_tf="$(cat "${TF_SN_DIR}/variables.tf")"
  outputs_tf="$(cat "${TF_SN_DIR}/outputs.tf")"

  assert_contains "${connector_tf}" "resource \"google_discovery_engine_data_connector\" \"servicenow\"" "Defines ServiceNow connector resource"
  assert_contains "${connector_tf}" "= \"servicenow\"" "Uses servicenow data_source"
  assert_contains "${connector_tf}" "dynamic \"action_config\"" "Defines dynamic action_config block for BAP actions"
  assert_contains "${connector_tf}" "dynamic \"bap_config\"" "Defines dynamic bap_config block for enabled_actions"
  assert_contains "${vars_tf}" "variable \"servicenow_secret_id\"" "Declares servicenow_secret_id variable"
  assert_contains "${vars_tf}" "variable \"servicenow_enabled_actions\"" "Declares servicenow_enabled_actions variable"
  assert_contains "${outputs_tf}" "output \"servicenow_connector_name\"" "Exports servicenow_connector_name output"
}

test_servicenow_scripts_and_cli_modes() {
  assert_file_exists "${PROJECT_ROOT}/configs/servicenow.env.example" "configs/servicenow.env.example exists"
  assert_file_exists "${PROJECT_ROOT}/deploy_servicenow_bootstrap.sh" "deploy_servicenow_bootstrap.sh exists"

  setup_mock_env
  local cfg="${PROJECT_ROOT}/configs/servicenow.env.example"

  # Test missing config error path
  local missing_rc=0
  load_servicenow_config "/nonexistent/servicenow.env" >/dev/null 2>&1 || missing_rc=$?
  assert_eq "1" "${missing_rc}" "load_servicenow_config fails on missing file"

  unset SERVICENOW_CLIENT_ID SERVICENOW_CLIENT_SECRET SERVICENOW_USERNAME SERVICENOW_PASSWORD
  load_servicenow_config "${cfg}" >/dev/null
  assert_eq "cymbal-servicenow-connector-credentials" "${SERVICENOW_SECRET_ID}" "Default SERVICENOW_SECRET_ID loaded"
  assert_eq "cymbal-sn" "${SERVICENOW_COLLECTION_ID}" "Default SERVICENOW_COLLECTION_ID loaded"

  # Validation fails when credentials are missing and Secret Manager returns empty
  export MOCK_CURL_GET_STATUS="404"
  export DRY_RUN="false"
  local val_rc=0
  validate_servicenow_config >/dev/null 2>&1 || val_rc=$?
  assert_eq "1" "${val_rc}" "validate_servicenow_config fails when credentials are missing"

  # Test auto-seeding Secret Manager secret when env vars are set and secret is 404
  export SERVICENOW_INSTANCE_URI="https://dev99999.service-now.com"
  export SERVICENOW_CLIENT_ID="sn-env-cid"
  export SERVICENOW_CLIENT_SECRET="sn-env-sec"
  export SERVICENOW_USERNAME="cymbal_ge_connector"
  export SERVICENOW_PASSWORD="sn-env-pwd"
  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  ensure_and_load_servicenow_secret_credentials >/dev/null
  local seed_calls
  seed_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${seed_calls}" "secrets?secretId=cymbal-servicenow-connector-credentials" "Auto-creates Secret Manager secret when 404"
  assert_contains "${seed_calls}" ":addVersion" "Auto-seeds initial JSON secret version"

  # Test loading credentials from Secret Manager JSON fallback when env vars are unset
  unset SERVICENOW_CLIENT_ID SERVICENOW_CLIENT_SECRET SERVICENOW_USERNAME SERVICENOW_PASSWORD
  export MOCK_CURL_GET_STATUS="200"
  local b64_json
  b64_json="$(printf '%s' '{"instance_uri":"https://dev99999.service-now.com","client_id":"sn-cid-111","client_secret":"sn-sec-222","username":"cymbal_ge_connector","password":"sn-pwd-333"}' | base64 | tr -d '\n')"
  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"}}"
  ensure_and_load_servicenow_secret_credentials >/dev/null
  unset MOCK_CURL_BODY
  assert_eq "sn-cid-111" "${SERVICENOW_CLIENT_ID}" "Loads SERVICENOW_CLIENT_ID from Secret Manager JSON"
  assert_eq "cymbal_ge_connector" "${SERVICENOW_USERNAME}" "Loads SERVICENOW_USERNAME from Secret Manager JSON"
  validate_servicenow_config >/dev/null

  # Test payload rendering (with and without actions)
  local sn_payload
  sn_payload="$(render_servicenow_connector_payload)"
  assert_contains "${sn_payload}" "\"dataSource\": \"servicenow\"" "Rendered payload sets dataSource=servicenow"
  assert_contains "${sn_payload}" "\"entityName\": \"knowledge_base\"" "Rendered payload includes knowledge_base entity"
  assert_contains "${sn_payload}" "\"entityName\": \"incident\"" "Rendered payload includes incident entity"
  assert_contains "${sn_payload}" "\"entityName\": \"catalog\"" "Rendered payload includes catalog entity"
  assert_contains "${sn_payload}" "\"createBapConnection\": true" "Rendered payload includes createBapConnection"
  assert_contains "${sn_payload}" "\"create_incident\"" "Rendered payload includes bapConfig.enabledActions"

  ENABLE_SERVICENOW_ACTIONS="false"
  local sn_payload_no_act
  sn_payload_no_act="$(render_servicenow_connector_payload)"
  ENABLE_SERVICENOW_ACTIONS="true"
  assert_contains "${sn_payload_no_act}" "\"dataSource\": \"servicenow\"" "Rendered payload without actions succeeds"

  # Test configure_servicenow_connector (404 -> setUpDataConnectorV2 POST), attach_servicenow_datastores_to_engines, and verify_servicenow_connector
  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  configure_servicenow_connector "true" >/dev/null
  local create_calls
  create_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${create_calls}" "setUpDataConnectorV2?collectionId=cymbal-sn" "Provisions ServiceNow connector via setUpDataConnectorV2 when 404"

  # Test configure_servicenow_connector (200 -> PATCH + engine & widget attachment)
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_BODY='{"name":"projects/cymbal-app-514110/locations/global/collections/default_collection/engines/cymbal-service-desk-app","state":"ACTIVE","dataStoreIds":["cymbal-m365-sp_file"]}'
  : > "${MOCK_CALL_LOG}"
  configure_servicenow_connector "false" >/dev/null
  run_servicenow_verification_and_summary >/dev/null
  deregister_servicenow_connector >/dev/null
  unset MOCK_CURL_BODY
  local sn_calls
  sn_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${sn_calls}" "collections/cymbal-sn/dataConnector?updateMask=actionConfig,bapConfig" "Patches ServiceNow BAP actions"
  assert_contains "${sn_calls}" "engines/cymbal-service-desk-app?updateMask=dataStoreIds" "Attaches ServiceNow datastores to target GE engines"

  # Test deploy_servicenow_main CLI modes (both live mock and dry-run)
  export MOCK_CURL_BODY="{\"name\":\"projects/cymbal-app-514110/secrets/cymbal-servicenow-connector-credentials\",\"payload\":{\"data\":\"${b64_json}\"}}"
  deploy_servicenow_main --help >/dev/null
  deploy_servicenow_main --config "${cfg}" >/dev/null
  deploy_servicenow_main --config "${cfg}" --curl-only >/dev/null
  deploy_servicenow_main --config "${cfg}" --terraform-only >/dev/null
  deploy_servicenow_main --config "${cfg}" --verify-only >/dev/null
  deploy_servicenow_main --config "${cfg}" --destroy >/dev/null
  unset MOCK_CURL_BODY

  deploy_servicenow_main --config "${cfg}" --dry-run >/dev/null
  deploy_servicenow_main --config "${cfg}" --terraform-only --dry-run >/dev/null
  deploy_servicenow_main --config "${cfg}" --curl-only --dry-run >/dev/null
  deploy_servicenow_main --config "${cfg}" --verify-only --dry-run >/dev/null
  deploy_servicenow_main --config "${cfg}" --destroy --dry-run >/dev/null

  # Test deploy_servicenow_bootstrap.sh dry-run
  local boot_out
  boot_out="$("${PROJECT_ROOT}/deploy_servicenow_bootstrap.sh" \
    --instance-uri "https://dev123456.service-now.com" \
    --admin-user "admin" \
    --customer-name "testsn" \
    --customer-domain "testsn.example.com" \
    --gcp-project-id "cymbal-app-514110" \
    --align-user-emails \
    --dry-run)"
  assert_contains "${boot_out}" "Phase 0D ServiceNow Bootstrap Complete!" "deploy_servicenow_bootstrap.sh dry-run completes"
  assert_file_exists "${PROJECT_ROOT}/configs/testsn-servicenow.env" "deploy_servicenow_bootstrap.sh generates configs/testsn-servicenow.env"
  rm -f "${PROJECT_ROOT}/configs/testsn-servicenow.env"

  teardown_mock_env
}

run_test_suite "ServiceNow Data Connector & Bootstrap Suite" \
  test_servicenow_terraform_files \
  test_servicenow_scripts_and_cli_modes
