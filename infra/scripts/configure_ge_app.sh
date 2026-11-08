#!/usr/bin/env bash
# Configures Gemini Enterprise App, Assistant, Identity/ACL settings, and
# optional fallback Data Store & Engine creation via authenticated curl REST API calls.

set -euo pipefail

render_acl_payload() {
  if [[ "${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}" == "THIRD_PARTY" && -n "${GE_WORKFORCE_IDENTITY_POOL:-}" ]]; then
    jq -n \
      --arg name "projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/aclConfig" \
      --arg idpType "${GE_IDENTITY_PROVIDER_TYPE}" \
      --arg pool "${GE_WORKFORCE_IDENTITY_POOL}" \
      '{name: $name, idpConfig: {idpType: $idpType, externalIdpConfig: {workforcePoolName: $pool}}}'
  else
    jq -n \
      --arg name "projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/aclConfig" \
      --arg idpType "${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}" \
      '{name: $name, idpConfig: {idpType: $idpType}}'
  fi
}

render_datastore_payload() {
  jq -n \
    --arg displayName "${GE_DATA_STORE_DISPLAY_NAME}" \
    --arg vertical "${GE_INDUSTRY_VERTICAL:-GENERIC}" \
    --arg contentConfig "${GE_DATA_STORE_CONTENT_CONFIG:-CONTENT_REQUIRED}" \
    --arg solutionType "${GE_SOLUTION_TYPE:-SOLUTION_TYPE_SEARCH}" \
    '{displayName: $displayName, industryVertical: $vertical, contentConfig: $contentConfig, solutionTypes: [$solutionType]}'
}

resolve_common_connector_datastore_ids() {
  if [[ "${GE_ENABLE_COMMON_CONNECTORS:-true}" == "false" ]]; then
    printf '[]'
    return 0
  fi
  jq -n --arg csv "${GE_COMMON_CONNECTOR_DATA_STORE_IDS:-}" '($csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | unique)'
}

render_engine_payload() {
  local common_ds_json
  common_ds_json="$(resolve_common_connector_datastore_ids)"
  jq -n \
    --arg displayName "${GE_APP_DISPLAY_NAME}" \
    --arg solutionType "${GE_SOLUTION_TYPE:-SOLUTION_TYPE_SEARCH}" \
    --arg appType "${GE_APP_TYPE:-APP_TYPE_INTRANET}" \
    --arg vertical "${GE_INDUSTRY_VERTICAL:-GENERIC}" \
    --arg dsId "${GE_DATA_STORE_ID}" \
    --argjson commonDs "${common_ds_json}" \
    --arg company "${GE_COMPANY_NAME:-Enterprise}" \
    --arg tier "${GE_SEARCH_TIER:-SEARCH_TIER_ENTERPRISE}" \
    --arg featAgentGallery "${GE_FEATURE_AGENT_GALLERY:-FEATURE_STATE_ON}" \
    --arg featNoCodeBuilder "${GE_FEATURE_NO_CODE_AGENT_BUILDER:-FEATURE_STATE_ON}" \
    --arg featAgentSharing "${GE_FEATURE_AGENT_SHARING:-FEATURE_STATE_OFF}" \
    --arg featSkills "${GE_FEATURE_SKILLS:-FEATURE_STATE_ON}" \
    --arg featSkillSharing "${GE_FEATURE_SKILL_SHARING:-FEATURE_STATE_ON}" \
    --arg featSkillSharingApproval "${GE_FEATURE_SKILL_SHARING_ADMIN_APPROVAL:-FEATURE_STATE_ON}" \
    --arg featProjects "${GE_FEATURE_PROJECTS:-FEATURE_STATE_ON}" \
    --arg featPromptGallery "${GE_FEATURE_PROMPT_GALLERY:-FEATURE_STATE_ON}" \
    --arg featModelSelector "${GE_FEATURE_MODEL_SELECTOR:-FEATURE_STATE_ON}" \
    --arg featNotebookLm "${GE_FEATURE_NOTEBOOK_LM:-FEATURE_STATE_ON}" \
    --arg featDeepResearch "${GE_FEATURE_DEEP_RESEARCH:-FEATURE_STATE_ON}" \
    --arg featPeopleSearch "${GE_FEATURE_PEOPLE_SEARCH:-FEATURE_STATE_ON}" \
    --arg featActions "${GE_FEATURE_ACTIONS:-FEATURE_STATE_ON}" \
    --arg featAudioOverview "${GE_FEATURE_AUDIO_OVERVIEW:-FEATURE_STATE_ON}" \
    --argjson allowAgentSharing "${GE_ALLOW_AGENT_SHARING:-false}" \
    --arg agentSharingPolicy "${GE_AGENT_SHARING_POLICY:-SHARING_POLICY_DISABLED}" \
    --argjson enableSkills "${GE_ENABLE_SKILLS:-true}" \
    --arg skillSharingPolicy "${GE_SKILL_SHARING_APPROVAL_POLICY:-ADMIN_APPROVAL_REQUIRED}" \
    --argjson requireAdminApprovalForSkills "${GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING:-true}" \
    --arg skillApproverGroup "${GE_SKILL_APPROVER_GROUP:-ge-platform-admins@${GE_CUSTOMER_DOMAIN:-example.com}}" \
    --argjson enableProjects "${GE_ENABLE_PROJECTS:-true}" \
    --argjson enablePkg "${GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH:-true}" \
    --argjson enableKnowledgeCatalog "${GE_ENABLE_KNOWLEDGE_CATALOG:-true}" \
    --arg taxonomy "${GE_KNOWLEDGE_CATALOG_TAXONOMY:-enterprise-taxonomy}" \
    --argjson retentionDays "${GE_CHAT_HISTORY_RETENTION_DAYS:-90}" \
    --argjson enableModelArmor "${GE_ENABLE_MODEL_ARMOR:-true}" \
    --arg maPrompt "${GE_MODEL_ARMOR_PROMPT_TEMPLATE:-}" \
    --arg maResponse "${GE_MODEL_ARMOR_RESPONSE_TEMPLATE:-}" \
    --arg maFailureMode "${GE_MODEL_ARMOR_FAILURE_MODE:-FAIL_CLOSED}" \
    --argjson enableObs "${GE_ENABLE_OBSERVABILITY:-true}" \
    --argjson obsAudit "${GE_OBSERVABILITY_AUDIT_LOGGING:-true}" \
    --argjson obsQr "${GE_OBSERVABILITY_QUERY_RESPONSE_LOGGING:-true}" \
    --argjson obsLatency "${GE_OBSERVABILITY_LATENCY_METRICS:-true}" \
    --arg obsBq "${GE_OBSERVABILITY_BQ_DATASET:-ge_observability}" \
    '{
      displayName: $displayName,
      solutionType: $solutionType,
      appType: $appType,
      industryVertical: $vertical,
      dataStoreIds: (([$dsId] + $commonDs) | map(select(length > 0)) | unique),
      commonConfig: {companyName: $company},
      searchEngineConfig: {searchTier: $tier, searchAddOns: ["SEARCH_ADD_ON_LLM"]},
      features: {
        "agent-gallery": $featAgentGallery,
        "no-code-agent-builder": $featNoCodeBuilder,
        "agent-sharing": $featAgentSharing,
        "skills": $featSkills,
        "skill-sharing": $featSkillSharing,
        "skill-sharing-admin-approval": $featSkillSharingApproval,
        "projects": $featProjects,
        "prompt-gallery": $featPromptGallery,
        "model-selector": $featModelSelector,
        "notebook-lm": $featNotebookLm,
        "deep-research": $featDeepResearch,
        "people-search": $featPeopleSearch,
        "actions": $featActions,
        "audio-overview": $featAudioOverview
      },
      sharingConfig: {
        allowAgentSharing: $allowAgentSharing,
        agentSharingPolicy: $agentSharingPolicy,
        enableSkills: $enableSkills,
        skillSharingPolicy: $skillSharingPolicy,
        requireAdminApprovalForSkillSharing: $requireAdminApprovalForSkills,
        skillApproverGroup: $skillApproverGroup,
        enableProjects: $enableProjects
      },
      knowledgeGraphConfig: {
        enablePrivateKnowledgeGraph: $enablePkg,
        enableKnowledgeCatalog: $enableKnowledgeCatalog,
        taxonomyId: $taxonomy
      },
      chatHistoryConfig: {
        retentionDays: $retentionDays
      },
      modelArmorConfig: {
        enableModelArmor: $enableModelArmor,
        promptTemplateName: $maPrompt,
        responseTemplateName: $maResponse,
        failureMode: $maFailureMode
      },
      observabilityConfig: {
        enableObservability: $enableObs,
        enableAuditLogging: $obsAudit,
        enableQueryResponseLogging: $obsQr,
        enableLatencyMetrics: $obsLatency,
        bigqueryExportDataset: $obsBq
      }
    }'
}

ensure_engine_common_connectors_attached() {
  if [[ "${GE_ENABLE_COMMON_CONNECTORS:-true}" == "false" ]]; then
    return 0
  fi
  local common_ds_json
  common_ds_json="$(resolve_common_connector_datastore_ids)"
  if [[ "$(jq -r 'length' <<<"${common_ds_json}")" -eq 0 ]]; then
    return 0
  fi

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}"
  local engine_url="${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}"
  local target_payload
  target_payload="$(jq -n --arg dsId "${GE_DATA_STORE_ID}" --argjson commonDs "${common_ds_json}" '{dataStoreIds: (([$dsId] + $commonDs) | map(select(length > 0)) | unique)}')"

  log_info "Ensuring Common Connectors (${GE_COMMON_CONNECTOR_COLLECTIONS:-M365}) are attached to Engine '${GE_APP_ID}'..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "${target_payload}" >/dev/null
    return 0
  fi

  local current_eng current_count missing_count
  current_eng="$(ge_curl_request "GET" "${engine_url}" "" "true" || echo '{}')"
  current_count="$(jq -r '(.dataStoreIds // []) | length' <<<"${current_eng}" 2>/dev/null || echo "0")"
  missing_count="$(jq -r --argjson target "${target_payload}" '($target.dataStoreIds - (.dataStoreIds // [])) | length' <<<"${current_eng}" 2>/dev/null || echo "1")"

  if [[ "${missing_count:-1}" -eq 0 ]]; then
    log_ok "Engine '${GE_APP_ID}' already has all Common Connector Data Stores attached (${current_count} total)."
    return 0
  fi

  if [[ "${current_count:-0}" -le 1 ]]; then
    log_info "Upgrading single-datastore Engine '${GE_APP_ID}' to Multi-Data-Store Engine with Common Connectors..."
    ge_curl_request "DELETE" "${engine_url}" "" "true" >/dev/null
    local full_eng_payload
    full_eng_payload="$(render_engine_payload)"
    ge_curl_request "POST" "${base_v1alpha}/${col_parent}/engines?engineId=${GE_APP_ID}" "${full_eng_payload}" >/dev/null
    log_ok "Engine '${GE_APP_ID}' upgraded to Multi-Data-Store Engine with Common Connectors."
  else
    local merged_payload
    merged_payload="$(jq -n --argjson cur "${current_eng}" --argjson target "${target_payload}" '{dataStoreIds: ((($cur.dataStoreIds // []) + $target.dataStoreIds) | unique)}')"
    ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "${merged_payload}" >/dev/null
    log_ok "Attached Common Connector Data Stores to Engine '${GE_APP_ID}'."
  fi
}

render_assistant_payload() {
  jq -n \
    --arg displayName "${GE_ASSISTANT_ID:-default_assistant}" \
    --arg instruction "${GE_ASSISTANT_SYSTEM_INSTRUCTION:-You are a helpful enterprise assistant.}" \
    --argjson enableWeb "${GE_ENABLE_WEB_SEARCH_GROUNDING:-true}" \
    --arg webType "${GE_WEB_GROUNDING_TYPE:-WEB_GROUNDING_TYPE_GOOGLE_SEARCH}" \
    --arg sessionTtl "${GE_CHAT_SESSION_TTL_SECONDS:-7776000s}" \
    --argjson retentionDays "${GE_CHAT_HISTORY_RETENTION_DAYS:-90}" \
    --argjson enableModelArmor "${GE_ENABLE_MODEL_ARMOR:-true}" \
    --arg maPrompt "${GE_MODEL_ARMOR_PROMPT_TEMPLATE:-}" \
    --arg maResponse "${GE_MODEL_ARMOR_RESPONSE_TEMPLATE:-}" \
    --arg maFailureMode "${GE_MODEL_ARMOR_FAILURE_MODE:-FAIL_CLOSED}" \
    '{
      displayName: $displayName,
      generationConfig: {
        systemInstruction: {
          additionalSystemInstruction: $instruction
        }
      },
      enableWebGrounding: $enableWeb,
      webGroundingType: $webType,
      sessionTtl: $sessionTtl,
      chatHistoryRetentionDays: $retentionDays,
      modelArmorConfig: {
        enableModelArmor: $enableModelArmor,
        promptTemplateName: $maPrompt,
        responseTemplateName: $maResponse,
        failureMode: $maFailureMode
      }
    }'
}

render_widget_config_payload() {
  local connector_map_json="${GE_CONNECTOR_DISPLAY_NAMES_JSON:-{}}"
  local collection_components_json
  collection_components_json="$(jq -n \
    --arg cols "${GE_COMMON_CONNECTOR_COLLECTIONS:-}" \
    --argjson map "${connector_map_json}" '
    ($cols | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $colList |
    [
      $colList[] as $cid |
      ($map[$cid] // {}) as $cfg |
      {
        name: $cid,
        displayName: ($cfg.collectionDisplayName // $cid),
        dataStoreComponents: [
          (($cfg.entities // {}) | to_entries[]) |
          {
            name: .key,
            displayName: .value
          }
        ]
      }
    ]' 2>/dev/null || echo '[]')"

  jq -n \
    --arg displayName "${GE_APP_DISPLAY_NAME:-Enterprise} Web Widget" \
    --argjson enableAutocomplete "${GE_ENABLE_AUTOCOMPLETE:-true}" \
    --arg autocompleteOrder "${GE_AUTOCOMPLETE_MATCHING_ORDER:-SUGGESTION_MATCHING_ORDER_PREFIX}" \
    --argjson enablePeople "${GE_ENABLE_PEOPLE_SUGGESTION:-true}" \
    --argjson enableRecent "${GE_ENABLE_RECENT_SEARCH:-true}" \
    --argjson enableFeedback "${GE_ENABLE_FEEDBACK:-true}" \
    --argjson allowDetailedComment "${GE_FEEDBACK_ALLOW_DETAILED_COMMENT:-true}" \
    --argjson enableUserEvents "${GE_ENABLE_USER_EVENT_COLLECTION:-true}" \
    --argjson userEventDays "${GE_USER_EVENT_RETENTION_DAYS:-365}" \
    --argjson enablePersonalization "${GE_ENABLE_SEARCH_PERSONALIZATION:-true}" \
    --argjson enableWebGrounding "${GE_ENABLE_WEB_SEARCH_GROUNDING:-true}" \
    --argjson allowAgentSharing "${GE_ALLOW_AGENT_SHARING:-false}" \
    --argjson enableSkills "${GE_ENABLE_SKILLS:-true}" \
    --arg skillSharingPolicy "${GE_SKILL_SHARING_APPROVAL_POLICY:-ADMIN_APPROVAL_REQUIRED}" \
    --argjson requireAdminApprovalForSkills "${GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING:-true}" \
    --argjson enableProjects "${GE_ENABLE_PROJECTS:-true}" \
    --argjson enablePkg "${GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH:-true}" \
    --arg logoUri "${GE_APP_LOGO_URI:-}" \
    --arg faviconUri "${GE_APP_FAVICON_URI:-}" \
    --argjson collectionComponents "${collection_components_json}" \
    '{
      displayName: $displayName,
      enableAutocomplete: $enableAutocomplete,
      enablePrivateKnowledgeGraph: $enablePkg,
      uiBranding: {
        logo: {url: $logoUri},
        favicon: {url: $faviconUri}
      },
      uiSettings: {
        interactionType: "SEARCH_WITH_FOLLOW_UPS",
        enableAutocomplete: $enableAutocomplete,
        autocompleteMatchingOrder: $autocompleteOrder,
        enablePeopleSuggestion: $enablePeople,
        enableRecentSearch: $enableRecent,
        enableQualityFeedback: $enableFeedback,
        allowDetailedFeedbackComment: $allowDetailedComment,
        enableUserEventCollection: $enableUserEvents,
        userEventRetentionDays: $userEventDays,
        enableSearchPersonalization: $enablePersonalization,
        enableWebAppGrounding: $enableWebGrounding,
        allowAgentSharing: $allowAgentSharing,
        enableSkills: $enableSkills,
        skillSharingPolicy: $skillSharingPolicy,
        requireAdminApprovalForSkillSharing: $requireAdminApprovalForSkills,
        enableProjects: $enableProjects
      },
      collectionComponents: $collectionComponents
    }'
}

configure_engine_features_and_widget() {
  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}"
  local engine_url="${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}"
  local widget_url="${engine_url}/widgetConfigs/default_search_widget_config"

  log_info "Configuring Engine Full Features (Agent Sharing Disabled, Skills + Admin Approval Enabled, Projects Enabled), Knowledge Catalog, Private Knowledge Graph, Model Armor, Chat Retention & Observability on '${GE_APP_ID}'..."
  local eng_payload
  eng_payload="$(render_engine_payload)"
  ge_curl_request "PATCH" "${engine_url}?updateMask=features,sharingConfig,knowledgeGraphConfig,chatHistoryConfig,modelArmorConfig,observabilityConfig" "${eng_payload}" "true" >/dev/null || true

  log_info "Configuring Widget Autocomplete, Feedback, User Event Collection, Logo & Admin Connector Display Names on '${GE_APP_ID}'..."
  local widget_payload
  widget_payload="$(render_widget_config_payload)"
  ge_curl_request "PATCH" "${widget_url}?updateMask=enableAutocomplete,enablePrivateKnowledgeGraph,uiBranding,uiSettings,collectionComponents" "${widget_payload}" "true" >/dev/null || true
  log_ok "Engine Full Feature Matrix, Widget, Branding, Autocomplete, Feedback, User Events, Model Armor & Observability configured."
}

render_cloud_identity_group_payload() {
  local customer_parent="$1" group_email="$2" display_name="$3" description="$4"
  jq -n --arg parent "${customer_parent}" --arg email "${group_email}" --arg displayName "${display_name}" --arg description "${description}" \
    '{parent: $parent, groupKey: {id: $email}, displayName: $displayName, description: $description, labels: {"cloudidentity.googleapis.com/groups.discussion_forum": ""}}'
}

render_cloud_identity_membership_payload() {
  local member_email="$1"
  jq -n --arg email "${member_email}" '{preferredMemberKey: {id: $email}, roles: [{name: "MEMBER"}]}'
}

render_engine_iam_policy_payload() {
  local group_email="$1" etag="${2:-}"
  local member="group:${group_email#group:}"
  if [[ -n "${etag}" ]]; then
    jq -n --arg member "${member}" --arg etag "${etag}" \
      '{policy: {etag: $etag, bindings: [{role: "roles/discoveryengine.agentspaceUser", members: [$member]}, {role: "roles/discoveryengine.agentspaceViewer", members: [$member]}, {role: "roles/discoveryengine.user", members: [$member]}, {role: "roles/discoveryengine.viewer", members: [$member]}]}}'
  else
    jq -n --arg member "${member}" \
      '{policy: {bindings: [{role: "roles/discoveryengine.agentspaceUser", members: [$member]}, {role: "roles/discoveryengine.agentspaceViewer", members: [$member]}, {role: "roles/discoveryengine.user", members: [$member]}, {role: "roles/discoveryengine.viewer", members: [$member]}]}}'
  fi
}

revoke_project_level_ge_access() {
  log_info "Synchronizing Project IAM policy on '${GCP_PROJECT_ID}' (removing unconditional bindings and setting 'Only ${GE_APP_ID}' condition)..."
  local crm_base="https://cloudresourcemanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "POST" "${crm_base}:getIamPolicy" '{"options":{"requestedPolicyVersion":3}}' >/dev/null
    return 0
  fi

  local domain="${GE_CUSTOMER_DOMAIN:-example.com}"
  local group_email="${GE_APP_ACCESS_GROUP:-${GE_APP_ID}-users@${domain}}"
  local group_member="group:${group_email#group:}"
  local cond_title="Only ${GE_APP_ID}"
  local cond_desc="Restricts access exclusively to ${GE_APP_DISPLAY_NAME:-${GE_APP_ID}} (${GE_APP_ID})"
  local cond_expr="resource.name.startsWith(\"projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}/engines/${GE_APP_ID}\") || resource.name.endsWith(\"/engines/${GE_APP_ID}\")"

  local policy_json set_payload
  policy_json="$(ge_curl_request "POST" "${crm_base}:getIamPolicy" '{"options":{"requestedPolicyVersion":3}}' "true" || echo '{}')"
  set_payload="$(jq -n --argjson pol "${policy_json}" --arg member "${group_member}" --arg title "${cond_title}" --arg desc "${cond_desc}" --arg expr "${cond_expr}" \
    '{policy: (($pol | .version = 3 | .bindings = ([(.bindings // [])[] | if (((.role == "roles/discoveryengine.user") or (.role == "roles/discoveryengine.viewer") or (.role == "roles/discoveryengine.agentspaceUser") or (.role == "roles/discoveryengine.agentspaceViewer")) and ((.condition // null) == null)) then .members |= map(select(startswith("serviceAccount:"))) elif (.condition.title? == $title) then empty else . end | select((.members | length) > 0)] + [{role: "roles/discoveryengine.user", members: [$member], condition: {title: $title, description: $desc, expression: $expr}}, {role: "roles/discoveryengine.agentspaceUser", members: [$member], condition: {title: $title, description: $desc, expression: $expr}}])))}')"
  ge_curl_request "POST" "${crm_base}:setIamPolicy" "${set_payload}" >/dev/null
  log_ok "Project IAM conditional binding ('${cond_title}') applied for '${group_member}' and unconditional bindings removed."
}

configure_engine_exclusive_group_iam() {
  local domain="${GE_CUSTOMER_DOMAIN:-example.com}"
  local group_email="${GE_APP_ACCESS_GROUP:-${GE_APP_ID}-users@${domain}}"
  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}"
  local engine_res="${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}"

  log_info "Enforcing exclusive Engine-level IAM on '${GE_APP_ID}' for group '${group_email}'..."
  local current_pol etag=""
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    current_pol="$(ge_curl_request "GET" "${engine_res}:getIamPolicy" "" "true" || echo '{}')"
    etag="$(jq -r '.etag // empty' <<<"${current_pol}" 2>/dev/null || true)"
  else
    ge_curl_request "GET" "${engine_res}:getIamPolicy" "" "true" >/dev/null
  fi

  local iam_payload
  iam_payload="$(render_engine_iam_policy_payload "${group_email}" "${etag}")"
  ge_curl_request "POST" "${engine_res}:setIamPolicy" "${iam_payload}" >/dev/null
  log_ok "Exclusive Engine-level IAM policy applied on '${GE_APP_ID}' -> 'group:${group_email}'."
}

configure_connector_oauth_iam() {
  local domain="${GE_CUSTOMER_DOMAIN:-example.com}"
  local group_email="${GE_APP_ACCESS_GROUP:-${GE_APP_ID}-users@${domain}}"
  local group_member="group:${group_email#group:}"
  local role_id="geConnectorAuthUser"
  local full_role="projects/${GCP_PROJECT_ID}/roles/${role_id}"

  log_info "Ensuring least-privilege Connector OAuth custom role ('${full_role}') and Collection IAM for '${group_member}'..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  local role_payload
  role_payload="$(jq -n --arg roleId "${role_id}" '{
    roleId: $roleId,
    role: {
      title: "Gemini Enterprise Connector OAuth User",
      description: "Least-privilege location and dataConnector OAuth permissions without granting cross-app Engine access.",
      stage: "GA",
      includedPermissions: [
        "discoveryengine.authorizations.storeUserAuthorization",
        "discoveryengine.collections.get",
        "discoveryengine.dataConnectors.acquireAccessToken",
        "discoveryengine.dataConnectors.acquireAndStoreRefreshToken",
        "discoveryengine.dataConnectors.buildActionInvocation",
        "discoveryengine.dataConnectors.checkRefreshToken",
        "discoveryengine.dataConnectors.executeAction",
        "discoveryengine.dataConnectors.queryAvailableActions",
        "discoveryengine.dataStores.get",
        "discoveryengine.locations.buildAuthorizationUrl",
        "discoveryengine.locations.completeExternalIdentities",
        "discoveryengine.locations.fetchAgentCards",
        "discoveryengine.locations.listConnectorSources",
        "discoveryengine.users.get",
        "discoveryengine.users.update"
      ]
    }
  }')"
  ge_curl_request "POST" "https://iam.googleapis.com/v1/projects/${GCP_PROJECT_ID}/roles" "${role_payload}" "true" >/dev/null || true

  # Bind group_member to geConnectorAuthUser on project
  local crm_base="https://cloudresourcemanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  local pol_json updated_pol
  pol_json="$(ge_curl_request "POST" "${crm_base}:getIamPolicy" '{"options":{"requestedPolicyVersion":3}}' "true" || echo '{}')"
  updated_pol="$(jq -n --argjson pol "${pol_json}" --arg role "${full_role}" --arg member "${group_member}" '{
    policy: (
      $pol | .version = 3 | .bindings = (
        ([(.bindings // [])[] | select(.role != $role)]) +
        [{
          role: $role,
          members: ((([(.bindings // [])[] | select(.role == $role) | .members[]?] + [$member]) | unique))
        }]
      )
    )
  }')"
  ge_curl_request "POST" "${crm_base}:setIamPolicy" "${updated_pol}" "true" >/dev/null || true

  # Grant Collection-level IAM on each shared connector collection
  if [[ -n "${GE_COMMON_CONNECTOR_COLLECTIONS:-}" ]]; then
    local base_v1alpha
    base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
    local IFS=','
    read -r -a cols <<<"${GE_COMMON_CONNECTOR_COLLECTIONS}"
    for raw_col in "${cols[@]}"; do
      local col
      col="$(printf '%s' "${raw_col}" | xargs)"
      [[ -z "${col}" ]] && continue
      local col_url="${base_v1alpha}/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${col}"
      local col_pol col_etag col_set_payload
      col_pol="$(ge_curl_request "GET" "${col_url}:getIamPolicy" "" "true" || echo '{}')"
      col_etag="$(jq -r '.etag // empty' <<<"${col_pol}" 2>/dev/null || true)"
      col_set_payload="$(jq -n --argjson cur "${col_pol}" --arg etag "${col_etag}" --arg member "${group_member}" '
        def add_mem(r):
          (([$cur.bindings[]? | select(.role == r) | .members[]?] + [$member]) | unique);
        {
          policy: (
            (if ($etag | length) > 0 then {etag: $etag} else {} end) + {
              bindings: [
                {role: "roles/discoveryengine.user", members: add_mem("roles/discoveryengine.user")},
                {role: "roles/discoveryengine.viewer", members: add_mem("roles/discoveryengine.viewer")},
                {role: "roles/discoveryengine.agentspaceUser", members: add_mem("roles/discoveryengine.agentspaceUser")}
              ]
            }
          )
        }')"
      ge_curl_request "POST" "${col_url}:setIamPolicy" "${col_set_payload}" "true" >/dev/null || true
    done
  fi
  log_ok "Connector OAuth custom role and Collection-level IAM configured for '${group_member}'."
}

resolve_cloud_identity_customer_id() {
  local cid="${GE_CLOUD_IDENTITY_CUSTOMER_ID:-}"
  if [[ -z "${cid}" && "${DRY_RUN:-false}" != "true" ]]; then
    local org_json
    org_json="$(ge_curl_request "POST" "https://cloudresourcemanager.googleapis.com/v1/organizations:search" '{}' "true" || echo '{}')"
    cid="$(jq -r '.organizations[0].owner.directoryCustomerId // empty' <<<"${org_json}" 2>/dev/null || true)"
  fi
  cid="${cid:-customers/my_customer}"
  if [[ "${cid}" != customers/* ]]; then
    cid="customers/${cid}"
  fi
  printf '%s' "${cid}"
}

ensure_app_cloud_identity_group() {
  local domain="${GE_CUSTOMER_DOMAIN:-example.com}"
  local group_email="${GE_APP_ACCESS_GROUP:-${GE_APP_ID}-users@${domain}}"
  export GE_APP_ACCESS_GROUP="${group_email}"
  local customer_parent
  customer_parent="$(resolve_cloud_identity_customer_id)"
  local group_display="${GE_APP_DISPLAY_NAME:-${GE_APP_ID}} Users"
  local group_desc="Dedicated access control group for Gemini Enterprise App ${GE_APP_ID}"
  local group_payload
  group_payload="$(render_cloud_identity_group_payload "${customer_parent}" "${group_email}" "${group_display}" "${group_desc}")"

  log_info "Ensuring dedicated Cloud Identity group '${group_email}' (${customer_parent}) exists for app '${GE_APP_ID}'..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/groups?initialGroupConfig=EMPTY" "${group_payload}" >/dev/null
    return 0
  fi

  local list_resp group_name
  list_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${customer_parent}" "" "true" || echo '{}')"
  group_name="$(jq -r --arg email "${group_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($email | ascii_downcase)) | .name' <<<"${list_resp}" 2>/dev/null | head -n 1 || true)"

  if [[ -z "${group_name}" ]]; then
    log_info "Creating Cloud Identity group '${group_email}'..."
    local create_resp
    create_resp="$(ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/groups?initialGroupConfig=EMPTY" "${group_payload}")"
    group_name="$(jq -r '.response.name // .name // empty' <<<"${create_resp}" 2>/dev/null || true)"
    if [[ "${group_name}" != groups/* ]]; then
      list_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${customer_parent}" "" "true" || echo '{}')"
      group_name="$(jq -r --arg email "${group_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($email | ascii_downcase)) | .name' <<<"${list_resp}" 2>/dev/null | head -n 1 || true)"
    fi
    log_ok "Cloud Identity group '${group_email}' (${group_name:-created}) provisioned."
  else
    log_ok "Cloud Identity group '${group_email}' (${group_name}) already exists."
  fi

  if [[ -n "${GE_APP_GROUP_MEMBERS:-}" && -n "${group_name}" && "${group_name}" == groups/* ]]; then
    local members_resp
    members_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${group_name}/memberships" "" "true" || echo '{}')"
    local IFS=','
    read -r -a raw_members <<<"${GE_APP_GROUP_MEMBERS}"
    for raw_m in "${raw_members[@]}"; do
      local member_email
      member_email="$(printf '%s' "${raw_m}" | xargs)"
      [[ -z "${member_email}" ]] && continue
      local existing_m
      existing_m="$(jq -r --arg m "${member_email}" '.memberships[]? | select((.preferredMemberKey.id | ascii_downcase) == ($m | ascii_downcase)) | .name' <<<"${members_resp}" 2>/dev/null | head -n 1 || true)"
      if [[ -z "${existing_m}" ]]; then
        log_info "Adding member '${member_email}' to group '${group_email}'..."
        local m_payload
        m_payload="$(render_cloud_identity_membership_payload "${member_email}")"
        ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/${group_name}/memberships" "${m_payload}" >/dev/null
      fi
    done
  fi
}

configure_gemini_enterprise_app() {
  local include_core_resources="${1:-false}"
  log_phase "CURL/API" "Configuring Gemini Enterprise App, ACLs, and Assistant via REST API"

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"
  local col_parent="${parent}/collections/${GE_COLLECTION_ID:-default_collection}"

  # 1. Configure Project/Location Identity & ACL Configuration
  log_info "Configuring Discovery Engine Identity/ACL settings (${GE_IDENTITY_PROVIDER_TYPE:-GSUITE})..."
  local acl_payload
  acl_payload="$(render_acl_payload)"
  ge_curl_request "PATCH" "${base_v1alpha}/${parent}/aclConfig" "${acl_payload}" >/dev/null
  log_ok "Identity/ACL configuration applied."

  # 2. If running in --curl-only mode (without Terraform), ensure Data Store & Engine exist via curl
  if [[ "${include_core_resources}" == "true" ]]; then
    log_info "Running in curl-only mode: Ensuring Data Store '${GE_DATA_STORE_ID}' exists via REST API..."
    local ds_payload
    ds_payload="$(render_datastore_payload)"
    ge_upsert_resource \
      "${base_v1alpha}/${col_parent}/dataStores/${GE_DATA_STORE_ID}" \
      "${base_v1alpha}/${col_parent}/dataStores?dataStoreId=${GE_DATA_STORE_ID}" \
      "${base_v1alpha}/${col_parent}/dataStores/${GE_DATA_STORE_ID}?updateMask=displayName" \
      "${ds_payload}" >/dev/null
    log_ok "Data Store '${GE_DATA_STORE_ID}' provisioned via REST API."

    log_info "Running in curl-only mode: Ensuring Gemini Enterprise Engine '${GE_APP_ID}' exists via REST API..."
    local eng_payload
    eng_payload="$(render_engine_payload)"
    ge_upsert_resource \
      "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}" \
      "${base_v1alpha}/${col_parent}/engines?engineId=${GE_APP_ID}" \
      "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}?updateMask=displayName,commonConfig" \
      "${eng_payload}" >/dev/null
    log_ok "Gemini Enterprise Engine '${GE_APP_ID}' provisioned via REST API."
  fi

  # 2b. Ensure Common Enterprise Connectors (e.g., M365) are attached to the Engine
  ensure_engine_common_connectors_attached

  # 3. Configure Gemini Enterprise Assistant settings (create via POST if missing, or update via PATCH)
  local assistant_id="${GE_ASSISTANT_ID:-default_assistant}"
  log_info "Configuring Gemini Enterprise Assistant '${assistant_id}' on engine '${GE_APP_ID}'..."
  local assistant_payload
  assistant_payload="$(render_assistant_payload)"
  ge_upsert_resource \
    "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}/assistants/${assistant_id}" \
    "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}/assistants?assistantId=${assistant_id}" \
    "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}/assistants/${assistant_id}?updateMask=generationConfig,enableWebGrounding,webGroundingType,sessionTtl,chatHistoryRetentionDays,modelArmorConfig" \
    "${assistant_payload}" >/dev/null
  log_ok "Gemini Enterprise Assistant '${assistant_id}' configured."

  # 3b. Configure Engine Full Features, Knowledge Catalog, PKG, Model Armor, Observability & Widget Settings
  configure_engine_features_and_widget

  # 4. Provision per-app Cloud Identity group & enforce exclusive Engine-level group IAM access + Connector OAuth IAM
  ensure_app_cloud_identity_group
  revoke_project_level_ge_access
  configure_engine_exclusive_group_iam
  configure_connector_oauth_iam
}
