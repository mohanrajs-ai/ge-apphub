#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=deploy.sh
source "${PROJECT_ROOT}/deploy.sh"

test_deploy_cli_help() {
  local help_out
  help_out="$(print_usage)"
  assert_contains "${help_out}" "--config" "Usage includes --config"
  assert_contains "${help_out}" "--dry-run" "Usage includes --dry-run"
  assert_contains "${help_out}" "--terraform-only" "Usage includes --terraform-only"
  assert_contains "${help_out}" "--curl-only" "Usage includes --curl-only"
  assert_contains "${help_out}" "--verify-only" "Usage includes --verify-only"
  assert_contains "${help_out}" "--destroy" "Usage includes --destroy"
}

test_deploy_end_to_end_and_modes() {
  setup_mock_env
  local cfg="${PROJECT_ROOT}/config.env.example"

  # 1. Full end-to-end execution (Terraform + curl + Verify)
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="200"
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${cfg}" >/dev/null
  local full_calls
  full_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${full_calls}" "terraform -chdir=" "Full run executes terraform"
  assert_contains "${full_calls}" "apply -auto-approve" "Full run applies terraform plan"
  assert_contains "${full_calls}" "aclConfig" "Full run configures ACLs via curl"
  assert_contains "${full_calls}" "assistants/default_assistant" "Full run configures Assistant via curl"

  # 2. Dry-Run mode (--dry-run)
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${cfg}" --dry-run >/dev/null
  local dry_calls
  dry_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${dry_calls}" "plan -out=tfplan" "Dry-run runs terraform plan"
  assert_not_contains "${dry_calls}" "apply -auto-approve" "Dry-run does not run terraform apply"

  # 3. Terraform-only mode (--terraform-only)
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${cfg}" --terraform-only >/dev/null
  local tf_only_calls
  tf_only_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${tf_only_calls}" "terraform -chdir=" "Terraform-only runs terraform"
  assert_not_contains "${tf_only_calls}" "aclConfig" "Terraform-only skips curl API calls"

  # 4. curl-only mode (--curl-only)
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${cfg}" --curl-only >/dev/null
  local curl_only_calls
  curl_only_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_not_contains "${curl_only_calls}" "apply -auto-approve" "curl-only skips terraform apply"
  assert_contains "${curl_only_calls}" "aclConfig" "curl-only runs curl API calls"

  # 5. Verify-only mode (--verify-only)
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${cfg}" --verify-only >/dev/null
  local verify_calls
  verify_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_not_contains "${verify_calls}" "apply -auto-approve" "verify-only skips terraform apply"
  assert_contains "${verify_calls}" "engines/${GE_APP_ID}" "verify-only checks engine endpoint"

  # 6. Destroy mode (--destroy) with remote GCS backend configured
  local tmp_cfg
  tmp_cfg="$(mktemp)"
  cp "${cfg}" "${tmp_cfg}"
  echo 'TF_STATE_BUCKET="my-tf-state-bucket"' >> "${tmp_cfg}"
  echo 'ENABLE_AGENT_REGISTRATION="true"' >> "${tmp_cfg}"
  : > "${MOCK_CALL_LOG}"
  deploy_main --config "${tmp_cfg}" --destroy >/dev/null
  local destroy_calls
  destroy_calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${destroy_calls}" "-X DELETE" "Destroy mode deregisters curl resources"
  assert_contains "${destroy_calls}" "destroy -auto-approve" "Destroy mode runs terraform destroy"
  rm -f "${tmp_cfg}"

  # 7. Help flag (--help)
  deploy_main --help >/dev/null

  teardown_mock_env
}

test_readme_documentation_completeness() {
  assert_file_exists "${PROJECT_ROOT}/README.md" "README.md exists"
  local readme
  readme="$(cat "${PROJECT_ROOT}/README.md")"
  assert_contains "${readme}" "config.env" "README documents config.env"
  assert_contains "${readme}" "--dry-run" "README documents --dry-run flag"
  assert_contains "${readme}" "--curl-only" "README documents --curl-only flag"
  assert_contains "${readme}" "roles/discoveryengine.admin" "README documents required IAM roles"
}

run_test_suite "Master Orchestrator CLI (deploy.sh)" \
  test_deploy_cli_help \
  test_deploy_end_to_end_and_modes \
  test_readme_documentation_completeness
