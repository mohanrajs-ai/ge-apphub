# Terraform and Provider Version Configuration for Microsoft Entra ID to Cloud Identity Sync
# Uses hashicorp/google and hashicorp/google-beta >= 7.7.0.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.7.0"
    }
  }
}

provider "google" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}
