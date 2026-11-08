# Input Variables for Microsoft 365 (M365) Discovery Engine Data Connectors
# Automatically populated via TF_VAR_* exports from configs/m365.env by scripts/configure_m365_connectors.sh

variable "project_id" {
  description = "Target Google Cloud Project ID where M365 Data Connectors will be deployed."
  type        = string
}

variable "region" {
  description = "Default Google Cloud region for regional resources (e.g., us-central1)."
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Discovery Engine multi-region location (global, us, or eu)."
  type        = string
  default     = "global"

  validation {
    condition     = contains(["global", "us", "eu"], var.location)
    error_message = "location must be one of: global, us, eu."
  }
}

variable "m365_collection_prefix" {
  description = "Prefix used for each M365 connector Collection ID (e.g., m365-sharepoint, m365-onedrive)."
  type        = string
  default     = "m365"
}

variable "m365_secret_id" {
  description = "Google Cloud Secret Manager Secret ID storing M365 Entra ID credentials in JSON format ({tenant_id, client_id, client_secret})."
  type        = string
  default     = "m365-connector-credentials"
}

variable "m365_tenant_id" {
  description = "Microsoft Entra ID (Azure AD) Directory / Tenant ID populated via TF_VAR_m365_tenant_id from the M365_TENANT_ID environment variable."
  type        = string
  default     = ""
}

variable "m365_client_id" {
  description = "Microsoft Entra ID Application (Client) ID populated via TF_VAR_m365_client_id from the M365_CLIENT_ID environment variable."
  type        = string
  default     = ""
}

variable "m365_client_secret" {
  description = "Microsoft Entra ID Application Client Secret populated via TF_VAR_m365_client_secret from the M365_CLIENT_SECRET environment variable."
  type        = string
  default     = ""
  sensitive   = true
}

variable "m365_connector_mode" {
  description = "Connector operating mode for M365 connectors (FEDERATED or DATA_INGESTION)."
  type        = string
  default     = "FEDERATED"

  validation {
    condition     = contains(["FEDERATED", "DATA_INGESTION", "FEDERATED_AND_EUA", "EUA", "ACTIONS"], var.m365_connector_mode)
    error_message = "m365_connector_mode must be one of: FEDERATED, DATA_INGESTION, FEDERATED_AND_EUA, EUA, ACTIONS."
  }
}

variable "m365_refresh_interval" {
  description = "Full sync refresh interval for M365 connectors (minimum 3h / 10800s, maximum 28 days)."
  type        = string
  default     = "86400s"
}

variable "enable_m365_actions" {
  description = "Set to 'true' to enable write/mutating Actions (action_config and bap_config) on M365 connectors."
  type        = string
  default     = "false"
}

# ------------------------------------------------------------------------------
# SharePoint Online Connector Variables
# ------------------------------------------------------------------------------
variable "enable_sharepoint_connector" {
  description = "Set to 'true' to provision the Microsoft SharePoint Online Data Connector."
  type        = string
  default     = "true"
}

variable "m365_sharepoint_data_source" {
  description = "Discovery Engine data_source identifier for SharePoint ('sharepoint_federated_search' or 'sharepoint')."
  type        = string
  default     = "sharepoint_federated_search"
}

variable "m365_sharepoint_connector_mode" {
  description = "Connector mode for SharePoint ('FEDERATED' or 'DATA_INGESTION')."
  type        = string
  default     = "FEDERATED"
}

variable "m365_sharepoint_instance_uri" {
  description = "SharePoint Online tenant instance URI (e.g., https://contoso.sharepoint.com)."
  type        = string
  default     = ""
}

variable "m365_sharepoint_entities" {
  description = "Comma-separated SharePoint entities to index/federate (site,page,file,comment,event)."
  type        = string
  default     = "file,page"
}

variable "m365_sharepoint_enabled_actions" {
  description = "Comma-separated write actions to enable on SharePoint when enable_m365_actions is true."
  type        = string
  default     = "create_folder,add_page,upload_document,add_list,list_lists,get_list_item,get_list_fields,check_in_document,check_out_document,discard_check_out_document,move_attachment_or_document,rename_attachment_or_document,update_file_properties,create_list_item,update_list_item,update_list,update_page,share_resource"
}

variable "m365_sharepoint_collection_id" {
  description = "Optional explicit Collection ID override for SharePoint connector."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# OneDrive Connector Variables
# ------------------------------------------------------------------------------
variable "enable_onedrive_connector" {
  description = "Set to 'true' to provision the Microsoft OneDrive Data Connector."
  type        = string
  default     = "false"
}

variable "m365_onedrive_connector_mode" {
  description = "Connector mode for OneDrive ('FEDERATED' or 'DATA_INGESTION')."
  type        = string
  default     = "FEDERATED"
}

variable "m365_onedrive_instance_uri" {
  description = "OneDrive instance URI (e.g., https://contoso-my.sharepoint.com). Defaults to sharepoint_instance_uri if empty."
  type        = string
  default     = ""
}

variable "m365_onedrive_entities" {
  description = "Comma-separated OneDrive entities to index/federate (file)."
  type        = string
  default     = "file"
}

variable "m365_onedrive_enabled_actions" {
  description = "Comma-separated write actions to enable on OneDrive when enable_m365_actions is true."
  type        = string
  default     = "upload_file,copy_file,copy_folder,move_file,move_folder,create_folder,rename_file,rename_folder,share_file_folder,update_file_properties"
}

variable "m365_onedrive_collection_id" {
  description = "Optional explicit Collection ID override for OneDrive connector."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Outlook (Exchange Online) Connector Variables
# ------------------------------------------------------------------------------
variable "enable_outlook_connector" {
  description = "Set to 'true' to provision the Microsoft Outlook Data Connector."
  type        = string
  default     = "false"
}

variable "m365_outlook_connector_mode" {
  description = "Connector mode for Outlook ('FEDERATED' or 'DATA_INGESTION')."
  type        = string
  default     = "FEDERATED"
}

variable "m365_outlook_instance_uri" {
  description = "Outlook / Microsoft Graph instance URI."
  type        = string
  default     = "https://outlook.office365.com"
}

variable "m365_outlook_entities" {
  description = "Comma-separated Outlook entities to index/federate (root,mail,mail-attachment,calendar,contact)."
  type        = string
  default     = "mail,mail-attachment,calendar,contact"
}

variable "m365_outlook_enabled_actions" {
  description = "Comma-separated write actions to enable on Outlook when enable_m365_actions is true."
  type        = string
  default     = "send_mail,create_message,update_message,reply_to_my_message,forward_mail,move_mail,add_attachments,download_attachments,create_event,update_event,rsvp_to_event,create_calendar,update_calendar,create_contact,update_contact"
}

variable "m365_outlook_collection_id" {
  description = "Optional explicit Collection ID override for Outlook connector."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Microsoft Teams Connector Variables
# ------------------------------------------------------------------------------
variable "enable_teams_connector" {
  description = "Set to 'true' to provision the Microsoft Teams Data Connector."
  type        = string
  default     = "false"
}

variable "m365_teams_connector_mode" {
  description = "Connector mode for Teams ('FEDERATED' or 'DATA_INGESTION')."
  type        = string
  default     = "FEDERATED"
}

variable "m365_teams_instance_uri" {
  description = "Microsoft Teams / Graph instance URI."
  type        = string
  default     = "https://teams.microsoft.com"
}

variable "m365_teams_entities" {
  description = "Comma-separated Microsoft Teams entities to index/federate (root,team,channel,channel-message,channel-file,chat-message)."
  type        = string
  default     = "channel-message,chat-message"
}

variable "m365_teams_enabled_actions" {
  description = "Comma-separated write actions to enable on Microsoft Teams when enable_m365_actions is true."
  type        = string
  default     = "send_channel_message,send_chat_message,create_channel"
}

variable "m365_teams_collection_id" {
  description = "Optional explicit Collection ID override for Teams connector."
  type        = string
  default     = ""
}
