# Gemini Enterprise App / Discovery Engine Search Engine Configuration

locals {
  per_app_data_store_ids = var.data_store_id != "" ? [google_discovery_engine_data_store.main[0].data_store_id] : []
  common_data_store_ids = [
    for id in split(",", var.common_connector_data_store_ids) : trimspace(id)
    if trimspace(id) != ""
  ]
}

resource "google_discovery_engine_search_engine" "main" {
  provider = google-beta

  project        = var.project_id
  location       = var.location
  collection_id  = var.collection_id
  engine_id      = var.app_id
  display_name   = var.app_display_name
  data_store_ids = distinct(concat(local.per_app_data_store_ids, local.common_data_store_ids))

  industry_vertical = var.industry_vertical
  app_type          = var.app_type

  common_config {
    company_name = var.company_name
  }

  search_engine_config {
    search_tier    = var.search_tier
    search_add_ons = var.enable_llm_addon == "true" ? ["SEARCH_ADD_ON_LLM"] : []
  }

  depends_on = [
    google_discovery_engine_data_store.main
  ]
}
