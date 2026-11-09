#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=deploy_identity.sh
if [[ -f "${PROJECT_ROOT}/deploy_identity.sh" ]]; then
  source "${PROJECT_ROOT}/deploy_identity.sh"
fi
# shellcheck source=deploy_gcp_directory_sync.sh
if [[ -f "${PROJECT_ROOT}/deploy_gcp_directory_sync.sh" ]]; then
  source "${PROJECT_ROOT}/deploy_gcp_directory_sync.sh"
fi

TF_IDENTITY_DIR="${PROJECT_ROOT}/terraform-identity"

test_identity_terraform_files() {
  assert_file_exists "${TF_IDENTITY_DIR}/versions.tf" "terraform-identity/versions.tf exists"
  assert_file_exists "${TF_IDENTITY_DIR}/variables.tf" "terraform-identity/variables.tf exists"
  assert_file_exists "${TF_IDENTITY_DIR}/identity.tf" "terraform-identity/identity.tf exists"
  assert_file_exists "${TF_IDENTITY_DIR}/outputs.tf" "terraform-identity/outputs.tf exists"

  local identity_tf vars_tf outputs_tf
  identity_tf="$(cat "${TF_IDENTITY_DIR}/identity.tf")"
  vars_tf="$(cat "${TF_IDENTITY_DIR}/variables.tf")"
  outputs_tf="$(cat "${TF_IDENTITY_DIR}/outputs.tf")"

  assert_contains "${vars_tf}" "variable \"project_id\"" "Declares project_id variable"
  assert_contains "${vars_tf}" "variable \"cloud_identity_customer_id\"" "Declares cloud_identity_customer_id variable"
  assert_contains "${vars_tf}" "variable \"m365_secret_id\"" "Declares m365_secret_id variable"
  assert_contains "${vars_tf}" "variable \"shared_identity_domain\"" "Declares shared_identity_domain variable"
  assert_contains "${vars_tf}" "variable \"dns_project_id\"" "Declares dns_project_id variable"
  assert_contains "${vars_tf}" "variable \"dns_zone_name\"" "Declares dns_zone_name variable"
  assert_contains "${vars_tf}" "variable \"synced_groups\"" "Declares synced_groups variable"
  assert_contains "${vars_tf}" "variable \"app_group_mappings\"" "Declares app_group_mappings variable"

  assert_contains "${identity_tf}" "data \"google_secret_manager_secret_version\" \"m365_credentials_latest\"" "Reads latest JSON secret version from Secret Manager"
  assert_contains "${identity_tf}" "resource \"google_dns_record_set\" \"domain_verification_txt\"" "Defines Cloud DNS verification TXT record resource"
  assert_contains "${identity_tf}" "resource \"google_cloud_identity_group\" \"synced_entra_groups\"" "Defines synced Entra Cloud Identity groups resource"
  assert_contains "${identity_tf}" "resource \"google_cloud_identity_group_membership\" \"synced_group_members\"" "Defines synced group members resource"
  assert_contains "${identity_tf}" "data \"google_cloud_identity_group_lookup\" \"target_app_groups\"" "Looks up existing Gemini Enterprise per-app groups"
  assert_contains "${identity_tf}" "resource \"google_cloud_identity_group_membership\" \"app_group_nested_members\"" "Defines Gemini Enterprise per-app group nesting resource"
  assert_contains "${identity_tf}" "resource \"google_iam_workforce_pool_provider\" \"entra_oidc\"" "Defines optional Workforce Pool OIDC provider using Secret Manager credentials"

  assert_contains "${outputs_tf}" "output \"synced_cloud_identity_groups\"" "Exports synced_cloud_identity_groups output"
  assert_contains "${outputs_tf}" "output \"entra_tenant_id\"" "Exports entra_tenant_id output resolved from Secret Manager"
}

test_identity_scripts_and_cli_modes() {
  assert_file_exists "${PROJECT_ROOT}/configs/identity.env.example" "configs/identity.env.example exists"
  assert_file_exists "${PROJECT_ROOT}/scripts/configure_identity.sh" "scripts/configure_identity.sh exists"
  assert_file_exists "${PROJECT_ROOT}/deploy_identity.sh" "deploy_identity.sh exists"

  setup_mock_env
  local cfg="${PROJECT_ROOT}/configs/identity.env.example"
  unset M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET
  load_identity_config "${cfg}" >/dev/null
  assert_eq "m365-connector-credentials" "${M365_SECRET_ID:-}" "Default M365_SECRET_ID loaded"
  assert_eq "example.com" "${SHARED_IDENTITY_DOMAIN:-}" "Default SHARED_IDENTITY_DOMAIN loaded"
  assert_eq "yourtenant.onmicrosoft.com" "${ENTRA_SOURCE_DOMAIN:-}" "Default ENTRA_SOURCE_DOMAIN loaded"

  # Validate fails when M365 secret environment variables are missing
  local val_rc=0
  validate_identity_config >/dev/null 2>&1 || val_rc=$?
  assert_eq "1" "${val_rc}" "validate_identity_config fails when M365 secret environment variables are missing"

  # Export M365 secret environment variables and verify validation passes
  export M365_TENANT_ID="env-tenant-123"
  export M365_CLIENT_ID="env-client-456"
  export M365_CLIENT_SECRET="env-secret-789"
  load_identity_config "${cfg}" >/dev/null
  validate_identity_config >/dev/null
  assert_eq "env-tenant-123" "${TF_VAR_m365_tenant_id}" "Exports TF_VAR_m365_tenant_id from environment variable"
  assert_eq "env-client-456" "${TF_VAR_m365_client_id}" "Exports TF_VAR_m365_client_id from environment variable"
  assert_eq "env-secret-789" "${TF_VAR_m365_client_secret}" "Exports TF_VAR_m365_client_secret from environment variable"

  # 1. Test Secret Manager JSON credential fallback resolution when env vars are unset
  unset M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET
  export MOCK_CURL_GET_STATUS="200"
  local b64_json
  b64_json="$(printf '%s' '{"tenant_id":"sm-tenant-123","client_id":"sm-client-456","client_secret":"sm-secret-xyz"}' | base64 | tr -d '\n')"
  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"}}"
  ensure_and_load_identity_secret_credentials >/dev/null
  unset MOCK_CURL_BODY
  assert_eq "sm-tenant-123" "${M365_TENANT_ID}" "Loads M365_TENANT_ID from Secret Manager JSON fallback"
  assert_eq "sm-client-456" "${M365_CLIENT_ID}" "Loads M365_CLIENT_ID from Secret Manager JSON fallback"
  assert_eq "sm-secret-xyz" "${M365_CLIENT_SECRET}" "Loads M365_CLIENT_SECRET from Secret Manager JSON fallback"

  # 2. Test Microsoft Graph OAuth2 token acquisition
  export MOCK_CURL_POST_STATUS="200"
  export MOCK_CURL_BODY='{"access_token":"mock-ms-graph-token-999"}'
  fetch_microsoft_graph_access_token >/dev/null
  unset MOCK_CURL_BODY
  assert_eq "mock-ms-graph-token-999" "${MS_GRAPH_ACCESS_TOKEN:-}" "Obtains MS_GRAPH_ACCESS_TOKEN via client_credentials grant"

  # 3. Test Bulk Entra UPN Domain Rewrite (@yourtenant.onmicrosoft.com -> @example.com)
  export ENTRA_BULK_UPDATE_UPN_DOMAIN="true"
  export ENTRA_UPN_REWRITE_EXCLUDE_USERS="admin@yourtenant.onmicrosoft.com"
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="204"
  export MOCK_CURL_BODY='{"value":[{"id":"u-1","displayName":"Adele Vance","userPrincipalName":"AdeleV@yourtenant.onmicrosoft.com","mailNickname":"AdeleV"},{"id":"u-admin","displayName":"Global Admin","userPrincipalName":"admin@yourtenant.onmicrosoft.com","mailNickname":"admin"}]}'
  : > "${MOCK_CALL_LOG}"
  bulk_update_entra_upn_domain >/dev/null
  unset MOCK_CURL_BODY
  local upn_calls
  upn_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${upn_calls}" "graph.microsoft.com/v1.0/users/u-1" "Calls Microsoft Graph PATCH to update AdeleV UPN to example.com"
  assert_not_contains "${upn_calls}" "graph.microsoft.com/v1.0/users/u-admin" "Skips excluded break-glass admin account during bulk UPN rewrite"

  # 4. Test Default GCP_DIRECTORY_SYNC Mode (delegates group/user sync to GCP Directory Sync, keeps synced_groups={})
  assert_file_exists "${PROJECT_ROOT}/deploy_gcp_directory_sync.sh" "deploy_gcp_directory_sync.sh exists"
  local tmp_tf_dir
  tmp_tf_dir="$(mktemp -d)"
  export TF_IDENTITY_DIR_OVERRIDE="${tmp_tf_dir}"
  export GCP_DIRECTORY_SYNC_MANIFEST_OUT="${tmp_tf_dir}/gcp-directory-sync-spec.json"
  export IDENTITY_SYNC_MODE="GCP_DIRECTORY_SYNC"
  export ENTRA_GROUP_FILTER="securityEnabled eq true"
  export ENTRA_TO_APP_GROUP_MAPPINGS="finance-team@yourtenant.onmicrosoft.com:finance-app-01-users@example.com,hr-team@example.com:hr-app-01-users@example.com"
  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"},\"access_token\":\"mock-ms-graph-token-999\",\"value\":[{\"id\":\"g-1\",\"displayName\":\"Finance Team\",\"mail\":\"finance-team@yourtenant.onmicrosoft.com\",\"mailNickname\":\"finance-team\",\"userPrincipalName\":\"AdeleV@yourtenant.onmicrosoft.com\",\"givenName\":\"Adele\",\"surname\":\"Vance\"}]}"
  sync_entra_entities_to_cloud_identity >/dev/null
  unset MOCK_CURL_BODY
  assert_file_exists "${tmp_tf_dir}/gcp-directory-sync-spec.json" "Writes GCP Directory Sync connector specification JSON"
  assert_file_exists "${tmp_tf_dir}/identity_entities.auto.tfvars.json" "Writes identity_entities.auto.tfvars.json for Terraform"
  local tfvars_json dir_sync_json
  tfvars_json="$(cat "${tmp_tf_dir}/identity_entities.auto.tfvars.json")"
  dir_sync_json="$(cat "${tmp_tf_dir}/gcp-directory-sync-spec.json")"
  assert_contains "${dir_sync_json}" "\"identity_sync_mode\": \"GCP_DIRECTORY_SYNC\"" "Manifest declares GCP_DIRECTORY_SYNC mode"
  assert_contains "${dir_sync_json}" "\"Directory.Read.All\"" "Manifest declares Directory.Read.All Graph permission"
  assert_contains "${tfvars_json}" "\"synced_groups\": {}" "GCP_DIRECTORY_SYNC mode sets synced_groups={} so Directory Sync owns group memberships"
  assert_contains "${tfvars_json}" "\"finance-team@example.com\"" "Generated tfvars JSON contains normalized synced group email in app_group_mappings"
  assert_contains "${tfvars_json}" "\"finance-app-01-users@example.com\"" "Generated tfvars JSON contains app_group_mappings target"

  # 4a. Test Entra Outbound SCIM 2.0 Provisioning Job & GE UserStore License Sync from Directory-Synced groups
  export ENABLE_ENTRA_SCIM_PROVISIONING_JOB="true"
  export AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS="true"
  export DIRECTORY_SYNC_MANAGED_GROUPS="ge-finance-users"
  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"},\"access_token\":\"mock-ms-graph-token-999\",\"id\":\"job-123\",\"value\":[{\"id\":\"sp-1\",\"displayName\":\"Google Cloud / G Suite Connector\"}],\"groups\":[{\"name\":\"groups/g-fin\",\"groupKey\":{\"id\":\"ge-finance-users@example.com\"}}],\"memberships\":[{\"preferredMemberKey\":{\"id\":\"adelev@example.com\"}},{\"preferredMemberKey\":{\"id\":\"ge-nested@example.com\"}}],\"userLicenses\":[{\"licenseConfig\":\"projects/p/locations/global/licenseConfigs/lc-1\"}]}"
  sync_entra_entities_to_cloud_identity >/dev/null
  unset MOCK_CURL_BODY
  export ENABLE_ENTRA_SCIM_PROVISIONING_JOB="false"

  # 4b. Test clean Entra group provisioning and SAML certificate/OU assignment
  export PROVISION_CLEAN_ENTRA_APP_GROUPS="true"
  export ENTRA_CLEAN_GROUPS_SPEC="ge-finance-users|Gemini Finance App Users|Dedicated Entra ID access group|AdeleV"
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_POST_STATUS="201"
  export MOCK_CURL_BODY='{"id":"g-new","value":[{"id":"u-1","userPrincipalName":"AdeleV@example.com"}]}'
  provision_clean_entra_app_groups >/dev/null
  export PROVISION_CLEAN_ENTRA_APP_GROUPS="false"

  # 4c. Test graceful handling of HTTP 403 Authorization_RequestDenied on Microsoft Graph
  export MOCK_CURL_GET_STATUS="403"
  export MOCK_CURL_BODY='{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges"}}'
  bulk_update_entra_upn_domain >/dev/null
  export MOCK_CURL_GET_STATUS="200"
  unset MOCK_CURL_BODY

  # 5. Test Discovery Engine aclConfig & Cloud Identity SSO configuration (including cert & OU assignment)
  local tmp_cert
  tmp_cert="$(mktemp)"
  echo "-----BEGIN CERTIFICATE-----MOCK-----END CERTIFICATE-----" > "${tmp_cert}"
  export ENABLE_CLOUD_IDENTITY_SAML_SSO="true"
  export SAML_IDP_CERT_FILE="${tmp_cert}"
  export SAML_TARGET_ORG_UNIT="orgUnits/03ph8a2z4ccykcf"
  export MOCK_CURL_BODY='{"name":"inboundSamlSsoProfiles/mockprof","spConfig":{"entityId":"https://accounts.google.com/samlrp/mockprof","assertionConsumerServiceUri":"https://accounts.google.com/samlrp/mockprof/acs"},"idpConfig":{"idpType":"GSUITE"}}'
  configure_cloud_identity_sso_and_acl >/dev/null
  rm -f "${tmp_cert}"
  unset SAML_IDP_CERT_FILE SAML_TARGET_ORG_UNIT MOCK_CURL_BODY

  # 6. Test deploy_identity_main CLI modes
  local tmp_cfg
  tmp_cfg="$(mktemp)"
  cp "${cfg}" "${tmp_cfg}"
  cat >> "${tmp_cfg}" <<'EOF'
TF_STATE_BUCKET="identity-tf-state-bucket"
ENTRA_BULK_UPDATE_UPN_DOMAIN="false"
SYNC_CLOUD_IDENTITY_USERS="false"
EOF

  export MOCK_CURL_BODY="{\"payload\":{\"data\":\"${b64_json}\"},\"access_token\":\"mock-token\",\"value\":[],\"idpConfig\":{\"idpType\":\"GSUITE\"}}"
  deploy_identity_main --config "${tmp_cfg}" >/dev/null
  deploy_identity_main --config "${tmp_cfg}" --dry-run >/dev/null
  deploy_identity_main --config "${tmp_cfg}" --sync-only >/dev/null
  deploy_identity_main --config "${tmp_cfg}" --terraform-only >/dev/null
  deploy_identity_main --config "${tmp_cfg}" --verify-only >/dev/null
  deploy_identity_main --config "${tmp_cfg}" --destroy >/dev/null
  deploy_identity_main --help >/dev/null

  # 7. Test deploy_gcp_directory_sync_main CLI modes
  deploy_gcp_directory_sync_main --config "${tmp_cfg}" --manifest-out "${tmp_tf_dir}/dir-sync.json" >/dev/null
  deploy_gcp_directory_sync_main --config "${tmp_cfg}" --enable-entra-scim-job --skip-licenses --dry-run >/dev/null
  deploy_gcp_directory_sync_main --config "${tmp_cfg}" --verify-only >/dev/null
  deploy_gcp_directory_sync_main --help >/dev/null
  unset MOCK_CURL_BODY
  unset TF_IDENTITY_DIR_OVERRIDE

  rm -rf "${tmp_tf_dir}" "${tmp_cfg}"
  teardown_mock_env
}

run_test_suite "Microsoft Entra ID to Cloud Identity Sync Suite" \
  test_identity_terraform_files \
  test_identity_scripts_and_cli_modes
