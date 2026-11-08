# ==============================================================================
# Stack 00: Microsoft Entra ID Automated Bootstrap (00-entra-bootstrap)
# ==============================================================================
# Declarative Terraform stack automating Step 0A:
#   - Entra OAuth 2.0 App Registration + Graph/SharePoint Permissions
#   - Tenant-Wide Admin Consent
#   - Zero-Touch Secret Manager Injection (projects/<project>/secrets/<secret>)
#   - Entra Gallery SAML 2.0 App ("Google Cloud / G Suite Connector")
# ==============================================================================

variable "gcp_project_id" {
  type = string
}

variable "customer_name" {
  type    = string
  default = "cymbal"
}

variable "customer_domain" {
  type    = string
  default = "cymbal.com"
}

variable "m365_secret_id" {
  type    = string
  default = "cymbal-m365-connector-credentials"
}

variable "saml_sp_entity_id" {
  type    = string
  default = ""
}

variable "saml_sp_acs_url" {
  type    = string
  default = ""
}

variable "create_entra_department_groups" {
  type    = bool
  default = true
}

module "entra_bootstrap" {
  source                         = "../../modules/entra-bootstrap"
  gcp_project_id                 = var.gcp_project_id
  customer_name                  = var.customer_name
  customer_domain                = var.customer_domain
  m365_secret_id                 = var.m365_secret_id
  saml_sp_entity_id              = var.saml_sp_entity_id
  saml_sp_acs_url                = var.saml_sp_acs_url
  create_entra_department_groups = var.create_entra_department_groups
}

output "entra_tenant_id" {
  value = module.entra_bootstrap.entra_tenant_id
}

output "entra_m365_client_id" {
  value = module.entra_bootstrap.entra_m365_client_id
}

output "gcp_secret_manager_resource" {
  value = module.entra_bootstrap.gcp_secret_manager_resource
}

output "saml_application_object_id" {
  value = module.entra_bootstrap.saml_application_object_id
}

output "saml_service_principal_object_id" {
  value = module.entra_bootstrap.saml_service_principal_object_id
}

output "saml_idp_entity_id" {
  value = module.entra_bootstrap.saml_idp_entity_id
}

output "saml_idp_sso_url" {
  value = module.entra_bootstrap.saml_idp_sso_url
}

output "saml_idp_certificate_pem" {
  value     = module.entra_bootstrap.saml_idp_certificate_pem
  sensitive = true
}
