#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

test_assertions_and_mocks() {
  assert_eq "hello" "hello" "assert_eq matches identical strings"
  assert_contains "hello world" "world" "assert_contains finds substring"

  setup_mock_env
  local token
  token="$(gcloud auth print-access-token)"
  assert_eq "mock-access-token-12345" "${token}" "mock gcloud returns token"

  local tf_ver
  tf_ver="$(terraform version)"
  assert_contains "${tf_ver}" "Terraform v1." "mock terraform returns version"
  teardown_mock_env
}

run_test_suite "Test Runner & Mock Helpers" test_assertions_and_mocks
