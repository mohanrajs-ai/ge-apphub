#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

# Source the implementation under test
# shellcheck source=scripts/lib/common.sh
source "${PROJECT_ROOT}/scripts/lib/common.sh"

test_logging_and_banners() {
  local tmp_log_dir
  tmp_log_dir="$(mktemp -d)"
  init_logging "${tmp_log_dir}"

  assert_file_exists "${LOG_FILE}" "init_logging creates timestamped log file"

  local banner_out
  banner_out="$(log_phase "PRE-FLIGHT" "Starting pre-flight checks")"
  assert_contains "${banner_out}" "[PRE-FLIGHT]" "log_phase prints phase tag"
  assert_contains "${banner_out}" "Starting pre-flight checks" "log_phase prints description"

  local info_out warn_out ok_out err_out
  info_out="$(log_info "Checking environment")"
  assert_contains "${info_out}" "[INFO]" "log_info prints [INFO]"

  ok_out="$(log_ok "Validation succeeded")"
  assert_contains "${ok_out}" "[OK]" "log_ok prints [OK]"

  warn_out="$(log_warn "Optional setting omitted")"
  assert_contains "${warn_out}" "[WARN]" "log_warn prints [WARN]"

  err_out="$(log_error "Something failed" 2>&1)"
  assert_contains "${err_out}" "[ERROR]" "log_error prints [ERROR]"
  log_error "Direct error trace test" >/dev/null || true
  load_config "/nonexistent/config.env" >/dev/null || true

  local log_contents
  log_contents="$(cat "${LOG_FILE}")"
  assert_contains "${log_contents}" "Starting pre-flight checks" "Log file records phase banner"
  assert_contains "${log_contents}" "Checking environment" "Log file records info message"

  rm -rf "${tmp_log_dir}"
}

test_config_loader_and_tf_var_export() {
  assert_file_exists "${PROJECT_ROOT}/config.env.example" "config.env.example exists"

  local sample_cfg
  sample_cfg="$(mktemp)"
  cp "${PROJECT_ROOT}/config.env.example" "${sample_cfg}"

  load_config "${sample_cfg}"

  assert_ne "" "${GCP_PROJECT_ID:-}" "GCP_PROJECT_ID loaded from config.env.example"
  assert_ne "" "${GE_APP_ID:-}" "GE_APP_ID loaded from config.env.example"
  assert_eq "${GCP_PROJECT_ID}" "${TF_VAR_project_id:-}" "TF_VAR_project_id automatically exported"
  assert_eq "${GE_LOCATION}" "${TF_VAR_location:-}" "TF_VAR_location automatically exported"
  assert_eq "${GE_APP_ID}" "${TF_VAR_app_id:-}" "TF_VAR_app_id automatically exported"
  assert_eq "${GE_DATA_STORE_ID}" "${TF_VAR_data_store_id:-}" "TF_VAR_data_store_id automatically exported"
  assert_ne "" "${GE_CUSTOMER_DOMAIN:-}" "GE_CUSTOMER_DOMAIN loaded or defaulted"
  assert_eq "${GE_APP_ID}-users@${GE_CUSTOMER_DOMAIN}" "${GE_APP_ACCESS_GROUP:-}" "GE_APP_ACCESS_GROUP derived as <GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>"
  assert_eq "${GE_APP_ACCESS_GROUP:-}" "${TF_VAR_app_access_group:-}" "TF_VAR_app_access_group automatically exported"
  assert_eq "${GE_CUSTOMER_DOMAIN:-}" "${TF_VAR_customer_domain:-}" "TF_VAR_customer_domain automatically exported"
  assert_contains "${GE_COMMON_CONNECTOR_COLLECTIONS:-}" "m365-sp" "GE_COMMON_CONNECTOR_COLLECTIONS loaded from configs/common_connectors.env"
  assert_contains "${GE_COMMON_CONNECTOR_DATA_STORE_IDS:-}" "m365-od_file" "GE_COMMON_CONNECTOR_DATA_STORE_IDS loaded from configs/common_connectors.env"
  assert_eq "${GE_COMMON_CONNECTOR_DATA_STORE_IDS:-}" "${TF_VAR_common_connector_data_store_ids:-}" "TF_VAR_common_connector_data_store_ids automatically exported"

  rm -f "${sample_cfg}"

  # Verify missing config file returns non-zero
  local missing_rc=0
  load_config "/nonexistent/config.env" >/dev/null 2>&1 || missing_rc=$?
  assert_ne "0" "${missing_rc}" "load_config fails when config file does not exist"
}

run_test_suite "Common Library & Configuration Loader" \
  test_logging_and_banners \
  test_config_loader_and_tf_var_export
