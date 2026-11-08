#!/usr/bin/env bash
# Shared test assertions and mock CLI helpers for Gemini Enterprise Deployment Automation

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Expected '${expected}' but got '${actual}'}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${expected}" == "${actual}" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] ${msg} (expected='${expected}', actual='${actual}')" >&2
    return 1
  fi
}

assert_ne() {
  local unexpected="$1"
  local actual="$2"
  local msg="${3:-Expected value not equal to '${unexpected}'}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${unexpected}" != "${actual}" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] ${msg} (got='${actual}')" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Expected output to contain '${needle}'}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${haystack}" == *"${needle}"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] ${msg}" >&2
    echo "         Needle:   ${needle}" >&2
    echo "         Haystack: ${haystack}" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Expected output NOT to contain '${needle}'}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${haystack}" != *"${needle}"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] ${msg}" >&2
    echo "         Found forbidden substring: ${needle}" >&2
    return 1
  fi
}

assert_file_exists() {
  local filepath="$1"
  local msg="${2:-Expected file '${filepath}' to exist}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -f "${filepath}" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] ${msg}" >&2
    return 1
  fi
}

setup_mock_env() {
  MOCK_TMP_DIR="$(mktemp -d)"
  MOCK_BIN_DIR="${MOCK_TMP_DIR}/bin"
  MOCK_CALL_LOG="${MOCK_TMP_DIR}/calls.log"
  mkdir -p "${MOCK_BIN_DIR}"
  : > "${MOCK_CALL_LOG}"
  ORIG_PATH="${PATH}"
  export MOCK_TMP_DIR MOCK_BIN_DIR MOCK_CALL_LOG ORIG_PATH

  # Mock gcloud
  cat > "${MOCK_BIN_DIR}/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "gcloud $*" >> "${MOCK_CALL_LOG}"
if [[ "${MOCK_GCLOUD_FAIL:-false}" == "true" ]]; then
  echo "ERROR: (gcloud.auth.print-access-token) You do not currently have an active account selected." >&2
  exit 1
fi
if [[ "$*" == *"print-access-token"* ]]; then
  echo "${MOCK_ACCESS_TOKEN:-mock-access-token-12345}"
  exit 0
fi
if [[ "$*" == *"config get-value project"* ]]; then
  echo "${MOCK_GCP_PROJECT:-mock-gcp-project}"
  exit 0
fi
if [[ "$*" == *"projects describe"* ]]; then
  echo "123456789012"
  exit 0
fi
echo "mock-gcloud-ok"
EOF
  chmod +x "${MOCK_BIN_DIR}/gcloud"

  # Mock terraform
  cat > "${MOCK_BIN_DIR}/terraform" <<'EOF'
#!/usr/bin/env bash
echo "terraform $*" >> "${MOCK_CALL_LOG}"
if [[ "${MOCK_TERRAFORM_FAIL:-false}" == "true" ]]; then
  echo "Error: Terraform execution failed" >&2
  exit 1
fi
if [[ "$*" == *"version"* ]]; then
  echo "Terraform v1.6.6"
  exit 0
fi
if [[ "$*" == *"output -json"* ]]; then
  cat <<'JSON'
{
  "engine_id": {"value": "mock-ge-engine"},
  "data_store_id": {"value": "mock-ge-datastore"},
  "collection_id": {"value": "default_collection"},
  "project_number": {"value": "123456789012"}
}
JSON
  exit 0
fi
echo "Terraform mock executed: $*"
EOF
  chmod +x "${MOCK_BIN_DIR}/terraform"

  # Mock curl
  cat > "${MOCK_BIN_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "${MOCK_CALL_LOG}"
# Parse -o <outfile> and -w %{http_code}
outfile=""
write_code=false
method="GET"
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      outfile="$2"
      shift 2
      ;;
    -w)
      write_code=true
      shift 2
      ;;
    -X)
      method="$2"
      shift 2
      ;;
    http*://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

status_code="${MOCK_CURL_STATUS:-200}"
default_mock_body='{"name":"projects/mock-project/locations/global/collections/default_collection/engines/mock-ge-engine","state":"ACTIVE"}'
response_body="${MOCK_CURL_BODY:-${default_mock_body}}"

if [[ "${method}" == "GET" && -n "${MOCK_CURL_GET_STATUS:-}" ]]; then
  status_code="${MOCK_CURL_GET_STATUS}"
fi
if [[ "${method}" == "POST" && -n "${MOCK_CURL_POST_STATUS:-}" ]]; then
  status_code="${MOCK_CURL_POST_STATUS}"
fi
if [[ "${method}" == "PATCH" && -n "${MOCK_CURL_PATCH_STATUS:-}" ]]; then
  status_code="${MOCK_CURL_PATCH_STATUS}"
fi
if [[ "${method}" == "DELETE" && -n "${MOCK_CURL_DELETE_STATUS:-}" ]]; then
  status_code="${MOCK_CURL_DELETE_STATUS}"
fi

if [[ -n "${outfile}" ]]; then
  printf '%s' "${response_body}" > "${outfile}"
else
  printf '%s' "${response_body}"
fi

if [[ "${write_code}" == "true" ]]; then
  printf '%s' "${status_code}"
fi

if [[ "${MOCK_CURL_NETWORK_FAIL:-false}" == "true" ]]; then
  exit 7
fi
exit 0
EOF
  chmod +x "${MOCK_BIN_DIR}/curl"

  export PATH="${MOCK_BIN_DIR}:${ORIG_PATH}"
}

teardown_mock_env() {
  if [[ -n "${ORIG_PATH:-}" ]]; then
    export PATH="${ORIG_PATH}"
  fi
  if [[ -n "${MOCK_TMP_DIR:-}" && -d "${MOCK_TMP_DIR}" ]]; then
    rm -rf "${MOCK_TMP_DIR}"
  fi
}

run_test_suite() {
  local suite_name="$1"
  shift
  echo "=== Running Suite: ${suite_name} ==="
  for test_fn in "$@"; do
    echo "  -> ${test_fn}"
    "${test_fn}"
  done
  echo "=== Suite Complete: ${suite_name} (${TESTS_PASSED}/${TESTS_RUN} assertions passed) ==="
  if [[ "${TESTS_FAILED}" -gt 0 ]]; then
    return 1
  fi
  return 0
}
