#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"
# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/preflight.sh
source "${PROJECT_ROOT}/scripts/preflight.sh"

test_preflight_success() {
  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export DRY_RUN="false"

  local rc=0
  run_preflight_checks >/dev/null || rc=$?
  assert_eq "0" "${rc}" "run_preflight_checks succeeds with valid config and tools"

  export DRY_RUN="true"
  check_gcloud_auth >/dev/null
  export DRY_RUN="false"
  teardown_mock_env
}

test_preflight_invalid_location_fails() {
  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export GE_LOCATION="invalid-region"

  local rc=0
  validate_required_config >/dev/null || rc=$?
  assert_ne "0" "${rc}" "validate_required_config rejects invalid GE_LOCATION"
  teardown_mock_env
}

test_preflight_missing_project_id_fails() {
  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export GCP_PROJECT_ID=""

  local rc=0
  validate_required_config >/dev/null || rc=$?
  assert_ne "0" "${rc}" "validate_required_config rejects empty GCP_PROJECT_ID"
  teardown_mock_env
}

test_preflight_gcloud_auth_failure() {
  setup_mock_env
  load_config "${PROJECT_ROOT}/config.env.example" >/dev/null
  export MOCK_GCLOUD_FAIL="true"

  local rc=0
  check_gcloud_auth >/dev/null || rc=$?
  assert_ne "0" "${rc}" "check_gcloud_auth fails when gcloud auth print-access-token fails"
  teardown_mock_env
}

test_preflight_missing_cli_tool() {
  setup_mock_env
  local rc=0
  check_cli_dependencies "gcloud" "nonexistent_cli_binary_xyz" >/dev/null || rc=$?
  assert_ne "0" "${rc}" "check_cli_dependencies fails when a required binary is missing"
  teardown_mock_env
}

run_test_suite "Pre-Flight Validation Checks" \
  test_preflight_success \
  test_preflight_invalid_location_fails \
  test_preflight_missing_project_id_fails \
  test_preflight_gcloud_auth_failure \
  test_preflight_missing_cli_tool
