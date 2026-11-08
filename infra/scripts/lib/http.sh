#!/usr/bin/env bash
# Authenticated curl HTTP wrapper, jq error parser, and idempotent REST helpers
# for Google Cloud Discovery Engine / Gemini Enterprise APIs.

set -euo pipefail

ge_api_base_url() {
  local location="${1:-global}"
  local version="${2:-v1alpha}"
  if [[ "${location}" == "global" ]]; then
    printf 'https://discoveryengine.googleapis.com/%s\n' "${version}"
  else
    printf 'https://%s-discoveryengine.googleapis.com/%s\n' "${location}" "${version}"
  fi
}

ge_remediation_hint() {
  local status_code="$1"
  local project_id="${2:-<PROJECT_ID>}"
  case "${status_code}" in
    401)
      printf 'Remediation: Run `gcloud auth login` and verify your active credentials before retrying.\n'
      ;;
    403)
      printf 'Remediation: Verify that the active principal holds `roles/discoveryengine.admin` and that `discoveryengine.googleapis.com` is enabled in project `%s`.\n' "${project_id}"
      ;;
    404)
      printf 'Remediation: Verify that the parent Collection, Data Store, or Engine ID exists in location `%s` of project `%s`.\n' "${GE_LOCATION:-global}" "${project_id}"
      ;;
    *)
      printf 'Remediation: Inspect the JSON payload and API parameters in your config file for project `%s`.\n' "${project_id}"
      ;;
  esac
}

ge_curl_request() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"
  local allow_404="${4:-false}"
  local project_id="${GCP_PROJECT_ID:-unknown-project}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] curl -sS -X ${method} '${url}' -H 'Authorization: Bearer \$ACCESS_TOKEN' -H 'Content-Type: application/json' -H 'X-Goog-User-Project: ${project_id}'${payload:+ -d '${payload}'}"
    printf '{"dryRun":true,"method":"%s","url":"%s"}\n' "${method}" "${url}"
    return 0
  fi

  local token
  token="$(gcloud auth application-default print-access-token --quiet 2>/dev/null || gcloud auth print-access-token --quiet)"

  local resp_file http_code
  resp_file="$(mktemp)"

  if [[ -n "${payload}" ]]; then
    http_code="$(curl --http1.1 -sS -o "${resp_file}" -w "%{http_code}" -X "${method}" "${url}" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${project_id}" \
      -d "${payload}")"
  else
    http_code="$(curl --http1.1 -sS -o "${resp_file}" -w "%{http_code}" -X "${method}" "${url}" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${project_id}")"
  fi

  local body
  body="$(cat "${resp_file}")"
  rm -f "${resp_file}"

  if [[ "${http_code}" == "404" && "${allow_404}" == "true" ]]; then
    return 44
  fi

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    local api_msg
    api_msg="$(printf '%s' "${body}" | jq -r '.error.message // .message // "Unknown API error"' 2>/dev/null || printf '%s' "${body}")"
    log_error "HTTP ${http_code} returned from ${method} ${url}: ${api_msg}"
    local hint
    hint="$(ge_remediation_hint "${http_code}" "${project_id}")"
    log_error "${hint}"
    return 1
  fi

  printf '%s\n' "${body}"
  return 0
}

ge_upsert_resource() {
  local get_url="$1"
  local post_url="$2"
  local patch_url="$3"
  local payload="$4"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "POST" "${post_url}" "${payload}"
    return 0
  fi

  local check_rc=0
  ge_curl_request "GET" "${get_url}" "" "true" >/dev/null || check_rc=$?

  if [[ "${check_rc}" -eq 44 ]]; then
    log_info "Resource not found at ${get_url}; creating via POST..."
    ge_curl_request "POST" "${post_url}" "${payload}"
  elif [[ "${check_rc}" -eq 0 ]]; then
    log_info "Resource already exists at ${get_url}; updating via PATCH..."
    ge_curl_request "PATCH" "${patch_url}" "${payload}"
  else
    return "${check_rc}"
  fi
}
