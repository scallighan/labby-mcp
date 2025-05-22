terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.22.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
    azapi = {
      source = "azure/azapi"
      version = "=2.3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-${local.loc_short}"
  resource_group_name = "DefaultResourceGroup-${local.loc_short}"
} 

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.gh_repo}-${random_string.unique.result}-${local.loc_for_naming}"
  location = var.location
  tags = local.tags
}

resource "azurerm_virtual_network" "default" {
  name                = "${local.func_name}-vnet-${local.loc_for_naming}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.38.0.0/16"]

  tags = local.tags
}

resource "azurerm_subnet" "default" {
  name                 = "default-subnet-${local.loc_for_naming}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.38.0.0/24"]
}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

}

resource "azurerm_role_assignment" "kv_officer" {
  scope                            = azurerm_key_vault.kv.id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = data.azurerm_client_config.current.object_id
}

resource "azurerm_application_insights" "app" {
  name                = "${local.func_name}-insights"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "other"
  workspace_id        = data.azurerm_log_analytics_workspace.default.id
}


resource "azurerm_storage_account" "sa" {
  name                     = "sa${local.func_name}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "sc" {
  name                  = "app-package-${local.func_name}"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

resource "azurerm_service_plan" "asp" {
  name                = "asp${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "FC1"
  os_type             = "Linux"

  tags = local.tags
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = "${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "https://${azurerm_storage_account.sa.name}.blob.core.windows.net/${azurerm_storage_container.sc.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.sa.primary_access_key
  runtime_name                = "python"
  runtime_version             = "3.12"
  maximum_instance_count      = 50
  instance_memory_in_mb       = 2048
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    application_insights_connection_string = azurerm_application_insights.app.connection_string
    http2_enabled = true
  }

  app_settings = {
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "blob" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "cog" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Cognitive Services Contributor"
  principal_id         = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}

resource "null_resource" "publish_func" {
  depends_on = [
    azurerm_role_assignment.blob
  ]
  triggers = {
    index = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "cd ../func && func azure functionapp publish ${azurerm_function_app_flex_consumption.this.name} --python"
  }
}
