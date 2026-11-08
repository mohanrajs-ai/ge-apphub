#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${PROJECT_ROOT}/scripts/lib/http.sh"

test_discovery_engine_base_url() {
  local url_global url_us url_eu
  url_global="$(ge_api_base_url "global" "v1alpha")"
  assert_eq "https://discoveryengine.googleapis.com/v1alpha" "${url_global}" "Global location uses standard endpoint"

  url_us="$(ge_api_base_url "us" "v1alpha")"
  assert_eq "https://us-discoveryengine.googleapis.com/v1alpha" "${url_us}" "US location uses us- regional endpoint"

  url_eu="$(ge_api_base_url "eu" "v1")"
  assert_eq "https://eu-discoveryengine.googleapis.com/v1" "${url_eu}" "EU location uses eu- regional endpoint"
}

test_dry_run_redacts_access_token() {
  setup_mock_env
  export DRY_RUN="true"
  export GCP_PROJECT_ID="test-proj"

  local tmp_out
  tmp_out="$(mktemp)"
  ge_curl_request "POST" "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines" '{"displayName":"Test"}' > "${tmp_out}"
  local out_content
  out_content="$(cat "${tmp_out}")"

  assert_contains "${out_content}" "[DRY-RUN]" "Dry run prints [DRY-RUN] prefix"
  assert_contains "${out_content}" "Bearer \$ACCESS_TOKEN" "Dry run uses redacted \$ACCESS_TOKEN placeholder"
  assert_not_contains "${out_content}" "mock-access-token-12345" "Dry run never leaks actual access token"

  export DRY_RUN="false"
  rm -f "${tmp_out}"
  teardown_mock_env
}

test_http_error_parsing_and_remediation() {
  setup_mock_env
  export DRY_RUN="false"
  export GCP_PROJECT_ID="test-proj"
  export MOCK_CURL_STATUS="403"
  export MOCK_CURL_BODY='{"error":{"code":403,"message":"Discovery Engine API has not been used in project test-proj before or it is disabled.","status":"PERMISSION_DENIED"}}'

  local tmp_err rc=0
  tmp_err="$(mktemp)"
  ge_curl_request "GET" "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app" "" 2>"${tmp_err}" >/dev/null || rc=$?
  ge_curl_request "GET" "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app" "" >/dev/null || true

  assert_ne "0" "${rc}" "HTTP 403 returns non-zero status code"
  local err_text
  err_text="$(cat "${tmp_err}")"
  assert_contains "${err_text}" "HTTP 403" "Error output reports HTTP 403"
  assert_contains "${err_text}" "roles/discoveryengine.admin" "Error output includes actionable IAM remediation hint"
  assert_contains "${err_text}" "discoveryengine.googleapis.com" "Error output mentions API enablement"

  assert_contains "$(ge_remediation_hint 401 test-proj)" "gcloud auth login" "401 remediation hint"
  assert_contains "$(ge_remediation_hint 404 test-proj)" "Collection, Data Store, or Engine ID" "404 remediation hint"
  assert_contains "$(ge_remediation_hint 500 test-proj)" "Inspect the JSON payload" "500 remediation hint"

  rm -f "${tmp_err}"
  teardown_mock_env
}

test_idempotent_upsert_helper() {
  setup_mock_env
  export DRY_RUN="false"
  export GCP_PROJECT_ID="test-proj"

  # Case 1: Resource does not exist (GET returns 404) -> triggers POST
  export MOCK_CURL_GET_STATUS="404"
  export MOCK_CURL_POST_STATUS="200"
  : > "${MOCK_CALL_LOG}"

  ge_upsert_resource \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines?engineId=my-app" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app?updateMask=displayName" \
    '{"displayName":"My App"}' >/dev/null

  local calls_404
  calls_404="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${calls_404}" "-X GET" "Checks resource existence via GET"
  assert_contains "${calls_404}" "-X POST" "Creates missing resource via POST when GET returns 404"

  # Case 2: Resource already exists (GET returns 200) -> triggers PATCH
  export MOCK_CURL_GET_STATUS="200"
  export MOCK_CURL_PATCH_STATUS="200"
  : > "${MOCK_CALL_LOG}"

  ge_upsert_resource \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines?engineId=my-app" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/test-proj/locations/global/engines/my-app?updateMask=displayName" \
    '{"displayName":"My App Updated"}' >/dev/null

  local calls_200
  calls_200="$(cat "${MOCK_CALL_LOG}")"
  assert_contains "${calls_200}" "-X GET" "Checks resource existence via GET"
  assert_contains "${calls_200}" "-X PATCH" "Updates existing resource via PATCH when GET returns 200"

  teardown_mock_env
}

run_test_suite "HTTP Wrapper & Idempotent curl Helpers" \
  test_discovery_engine_base_url \
  test_dry_run_redacts_access_token \
  test_http_error_parsing_and_remediation \
  test_idempotent_upsert_helper
