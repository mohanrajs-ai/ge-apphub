#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

TF_DIR="${PROJECT_ROOT}/terraform"

test_terraform_versions_variables_outputs() {
  assert_file_exists "${TF_DIR}/versions.tf" "terraform/versions.tf exists"
  assert_file_exists "${TF_DIR}/variables.tf" "terraform/variables.tf exists"
  assert_file_exists "${TF_DIR}/outputs.tf" "terraform/outputs.tf exists"

  local versions_content vars_content outputs_content
  versions_content="$(cat "${TF_DIR}/versions.tf")"
  vars_content="$(cat "${TF_DIR}/variables.tf")"
  outputs_content="$(cat "${TF_DIR}/outputs.tf")"

  assert_contains "${versions_content}" "hashicorp/google" "versions.tf declares hashicorp/google provider"
  assert_contains "${versions_content}" "hashicorp/google-beta" "versions.tf declares hashicorp/google-beta provider"
  assert_contains "${versions_content}" "user_project_override = true" "versions.tf enables user_project_override for ADC quota project"
  assert_contains "${versions_content}" "billing_project       = var.project_id" "versions.tf sets billing_project to var.project_id"

  local expected_vars=(
    "project_id"
    "region"
    "location"
    "collection_id"
    "app_id"
    "app_display_name"
    "company_name"
    "solution_type"
    "search_tier"
    "enable_llm_addon"
    "industry_vertical"
    "data_store_id"
    "data_store_display_name"
    "data_store_content_config"
    "backing_storage_type"
    "gcs_bucket_name"
    "bq_dataset_id"
    "iam_viewer_members"
    "customer_domain"
    "cloud_identity_customer_id"
    "app_access_group"
    "app_group_members"
    "common_connector_data_store_ids"
  )
  for v in "${expected_vars[@]}"; do
    assert_contains "${vars_content}" "variable \"${v}\"" "variables.tf declares variable '${v}'"
  done

  assert_contains "${outputs_content}" "output \"engine_id\"" "outputs.tf exports engine_id"
  assert_contains "${outputs_content}" "output \"data_store_id\"" "outputs.tf exports data_store_id"
  assert_contains "${outputs_content}" "output \"collection_id\"" "outputs.tf exports collection_id"
  assert_contains "${outputs_content}" "output \"project_number\"" "outputs.tf exports project_number"
  assert_contains "${outputs_content}" "output \"app_access_group\"" "outputs.tf exports app_access_group"
}

test_terraform_resources_and_anti_patterns() {
  assert_file_exists "${TF_DIR}/apis_and_iam.tf" "terraform/apis_and_iam.tf exists"
  assert_file_exists "${TF_DIR}/data_stores.tf" "terraform/data_stores.tf exists"
  assert_file_exists "${TF_DIR}/engine.tf" "terraform/engine.tf exists"

  local apis_iam ds engine all_tf
  apis_iam="$(cat "${TF_DIR}/apis_and_iam.tf")"
  ds="$(cat "${TF_DIR}/data_stores.tf")"
  engine="$(cat "${TF_DIR}/engine.tf")"
  all_tf="$(cat "${TF_DIR}"/*.tf)"

  # Verify required GCP APIs and per-app Cloud Identity group resources (no project-wide ge_viewers)
  assert_contains "${apis_iam}" "resource \"google_project_service\" \"main\"" "apis_and_iam.tf enables required GCP APIs"
  assert_contains "${apis_iam}" "discoveryengine.googleapis.com" "apis_and_iam.tf includes discoveryengine.googleapis.com"
  assert_contains "${apis_iam}" "aiplatform.googleapis.com" "apis_and_iam.tf includes aiplatform.googleapis.com"
  assert_contains "${apis_iam}" "cloudidentity.googleapis.com" "apis_and_iam.tf includes cloudidentity.googleapis.com"
  assert_contains "${apis_iam}" "resource \"google_cloud_identity_group\" \"app_group\"" "apis_and_iam.tf defines per-app google_cloud_identity_group"
  assert_contains "${apis_iam}" "resource \"google_cloud_identity_group_membership\" \"app_group_members\"" "apis_and_iam.tf defines google_cloud_identity_group_membership"
  assert_not_contains "${apis_iam}" "resource \"google_project_iam_member\" \"ge_viewers\"" "apis_and_iam.tf does not grant project-wide discoveryengine.viewer"
  assert_not_contains "${all_tf}" "google_project_iam_policy" "Never uses authoritative google_project_iam_policy"

  # Verify backing storage and Discovery Engine Data Store
  assert_contains "${ds}" "resource \"google_storage_bucket\"" "data_stores.tf defines optional GCS bucket"
  assert_contains "${ds}" "resource \"google_bigquery_dataset\"" "data_stores.tf defines optional BigQuery dataset"
  assert_contains "${ds}" "resource \"google_discovery_engine_data_store\" \"main\"" "data_stores.tf defines Discovery Engine Data Store"

  # Verify Gemini Enterprise Search Engine
  assert_contains "${engine}" "resource \"google_discovery_engine_search_engine\" \"main\"" "engine.tf defines Gemini Enterprise Search Engine"
  assert_contains "${engine}" "common_connector_data_store_ids" "engine.tf merges common_connector_data_store_ids into data_store_ids"
  assert_contains "${engine}" "search_engine_config" "engine.tf configures search_engine_config"
  assert_contains "${engine}" "search_tier" "engine.tf configures search_tier"
  assert_contains "${engine}" "search_add_ons" "engine.tf configures search_add_ons"

  # Validate balanced braces across all .tf files
  python3 - "${TF_DIR}" <<'PYEOF'
import glob
import os
import sys

tf_dir = sys.argv[1]
for path in sorted(glob.glob(os.path.join(tf_dir, "*.tf"))):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if text.count("{") != text.count("}"):
        print(f"Unbalanced braces in {path}", file=sys.stderr)
        sys.exit(1)
PYEOF
}

run_test_suite "Terraform Provider, Variables & Outputs" \
  test_terraform_versions_variables_outputs \
  test_terraform_resources_and_anti_patterns
