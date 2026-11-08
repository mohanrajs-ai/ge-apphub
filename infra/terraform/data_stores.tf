# Backing Storage (GCS / BigQuery) and Discovery Engine Data Store

resource "google_storage_bucket" "ge_docs" {
  count = var.backing_storage_type == "GCS" && var.gcs_bucket_name != "" ? 1 : 0

  project                     = var.project_id
  name                        = var.gcs_bucket_name
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.main["storage.googleapis.com"]]
}

resource "google_bigquery_dataset" "ge_data" {
  count = var.backing_storage_type == "BIGQUERY" && var.bq_dataset_id != "" ? 1 : 0

  project    = var.project_id
  dataset_id = var.bq_dataset_id
  location   = var.region

  depends_on = [google_project_service.main["bigquery.googleapis.com"]]
}

resource "google_discovery_engine_data_store" "main" {
  count    = var.data_store_id != "" ? 1 : 0
  provider = google-beta

  project                     = var.project_id
  location                    = var.location
  data_store_id               = var.data_store_id
  display_name                = var.data_store_display_name
  industry_vertical           = var.industry_vertical
  content_config              = var.data_store_content_config
  solution_types              = [var.solution_type]
  create_advanced_site_search = false

  depends_on = [
    google_project_service.main["discoveryengine.googleapis.com"],
    google_storage_bucket.ge_docs,
    google_bigquery_dataset.ge_data
  ]
}
