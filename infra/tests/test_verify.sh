#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${PROJECT_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/verify.sh
source "${PROJECT_ROOT}/scripts/verify.sh"

test_post_deploy_verification_and_summary() {
  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export DRY_RUN="false"
  export ENABLE_AGENT_REGISTRATION="true"
  export MOCK_CURL_GET_STATUS="200"

  local tmp_out
  tmp_out="$(mktemp)"
  run_verification_and_summary > "${tmp_out}"
  local out_text
  out_text="$(cat "${tmp_out}")"

  assert_contains "${out_text}" "[VERIFY]" "Prints [VERIFY] phase banner"
  assert_contains "${out_text}" "[SUMMARY]" "Prints [SUMMARY] phase banner"
  assert_contains "${out_text}" "${GE_APP_ID}" "Summary includes Gemini Enterprise App ID"
  assert_contains "${out_text}" "${GE_DATA_STORE_ID}" "Summary includes Data Store ID"
  assert_contains "${out_text}" "${GE_APP_ACCESS_GROUP}" "Summary includes Dedicated App Access Group"
  assert_contains "${out_text}" "Common Connectors" "Summary includes Common Connectors line"
  assert_contains "${out_text}" "m365-sp" "Summary includes M365 common connector collections"
  assert_contains "${out_text}" "${AGENT_ID}" "Summary includes Registered Agent ID"
  assert_contains "${out_text}" "https://console.cloud.google.com/gen-app-builder/engines" "Summary includes GCP Console link"

  local calls
  calls="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${calls}" "engines/${GE_APP_ID}:getIamPolicy" "Verifies Engine-level IAM policy during verification"

  # Also test when ENABLE_AGENT_REGISTRATION=false
  export ENABLE_AGENT_REGISTRATION="false"
  run_verification_and_summary >/dev/null

  rm -f "${tmp_out}"
  teardown_mock_env
}

run_test_suite "Post-Deployment Verification & Summary Reporter" \
  test_post_deploy_verification_and_summary
