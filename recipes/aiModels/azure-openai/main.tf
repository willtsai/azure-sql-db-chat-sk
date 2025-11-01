terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
  }
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "context" {
  description = "This variable contains Radius recipe context."
  type        = any
}

variable "sku_name" {
  type        = string
  description = "SKU name for the Cognitive Account (S0, S1, etc.)"
  default     = "S0"
}

variable "capacity" {
  type        = number
  description = "Deployment capacity (tokens per minute in thousands)"
  default     = 10
}

variable "api_version" {
  type        = string
  description = "Azure OpenAI API version"
  default     = "2024-02-01"
}

variable "public_network_access" {
  type        = string
  description = "Enable or disable public network access"
  default     = "Enabled"
}

variable "tags" {
  type        = map(string)
  description = "Custom tags to apply to resources"
  default     = {}
}

variable "enable_pii_filter" {
  type        = bool
  description = "Enable PII (Personally Identifiable Information) content filter as an output filter"
  default     = false
}

locals {
  uniqueName = var.context.resource.name
  model      = var.context.resource.properties.model

  # Map model names to Azure OpenAI deployment configurations
  model_config = {
    "gpt-4" = {
      format  = "OpenAI"
      name    = "gpt-4"
      version = "turbo-2024-04-09"
    }
    "gpt-35-turbo" = {
      format  = "OpenAI"
      name    = "gpt-35-turbo"
      version = "0125"
    }
    "text-embedding-3-small" = {
      format  = "OpenAI"
      name    = "text-embedding-3-small"
      version = "1"
    }
    "text-embedding-ada-002" = {
      format  = "OpenAI"
      name    = "text-embedding-ada-002"
      version = "2"
    }
    "gpt-4o" = {
      format  = "OpenAI"
      name    = "gpt-4o"
      version = "2024-05-13"
    }
  }

  # Select the model configuration
  selected_model = lookup(local.model_config, local.model, {
    format  = "OpenAI"
    name    = local.model
    version = "1"
  })

  # Merge Radius tags with user-provided tags
  radius_tags = {
    "radapp.io-environment"    = var.context.environment.name
    "radapp.io-application"    = var.context.application.name
    "radapp.io-resource"       = var.context.resource.name
    "radapp.io-resource-type"  = "Radius.Resources-aiModels"
  }
  all_tags = merge(var.tags, local.radius_tags)
}

resource "azurerm_cognitive_account" "openai" {
  name                          = local.uniqueName
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = var.sku_name
  custom_subdomain_name         = local.uniqueName
  public_network_access_enabled = var.public_network_access == "Enabled" ? true : false

  tags = local.all_tags
}

# Content filter for PII detection (only created if enabled)
resource "azurerm_cognitive_account_rai_policy" "pii_filter" {
  count                = var.enable_pii_filter ? 1 : 0
  name                 = "${local.uniqueName}-pii-filter"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  content_filter {
    name                  = "pii"
    blocking_enabled      = true
    enabled               = true
    severity_threshold    = "Low"
    source_type           = "Output"
  }
}

resource "azurerm_cognitive_deployment" "model" {
  name                   = local.model
  cognitive_account_id   = azurerm_cognitive_account.openai.id
  rai_policy_name        = var.enable_pii_filter ? azurerm_cognitive_account_rai_policy.pii_filter[0].name : "Microsoft.Default"
  version_upgrade_option = "OnceNewDefaultVersionAvailable"

  model {
    format  = local.selected_model.format
    name    = local.selected_model.name
    version = local.selected_model.version
  }

  sku {
    name     = "Standard"
    capacity = var.capacity
  }

  depends_on = [
    azurerm_cognitive_account_rai_policy.pii_filter
  ]
}

output "result" {
  value = {
    # Resource IDs for tracking
    resources = concat(
      [
        azurerm_cognitive_account.openai.id,
        azurerm_cognitive_deployment.model.id
      ],
      var.enable_pii_filter ? [azurerm_cognitive_account_rai_policy.pii_filter[0].id] : []
    )

    # Public values
    values = {
      apiVersion          = var.api_version
      endpoint            = azurerm_cognitive_account.openai.endpoint
      model               = local.model
      deployment          = azurerm_cognitive_deployment.model.name
      location            = var.location
      capacity            = var.capacity
      skuName             = var.sku_name
      publicNetworkAccess = var.public_network_access
      piiFilterEnabled    = var.enable_pii_filter
    }

    # Sensitive outputs
    secrets = {
      apiKey = azurerm_cognitive_account.openai.primary_access_key
    }
  }
  sensitive = true
}