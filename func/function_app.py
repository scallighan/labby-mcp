import azure.functions as func
import json
import logging
import os

from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.costmanagement import CostManagementClient

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Constants for the Azure Blob Storage container, file, and blob path
_SNIPPET_NAME_PROPERTY_NAME = "snippetname"
_SNIPPET_PROPERTY_NAME = "snippet"
_BLOB_PATH = "snippets/{mcptoolargs." + _SNIPPET_NAME_PROPERTY_NAME + "}.json"

subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")

class ToolProperty:
    def __init__(self, property_name: str, property_type: str, description: str):
        self.propertyName = property_name
        self.propertyType = property_type
        self.description = description

    def to_dict(self):
        return {
            "propertyName": self.propertyName,
            "propertyType": self.propertyType,
            "description": self.description,
        }


# Define the tool properties using the ToolProperty class
tool_properties_save_snippets_object = [
    ToolProperty(_SNIPPET_NAME_PROPERTY_NAME, "string", "The name of the snippet."),
    ToolProperty(_SNIPPET_PROPERTY_NAME, "string", "The content of the snippet."),
]

tool_properties_get_snippets_object = [ToolProperty(_SNIPPET_NAME_PROPERTY_NAME, "string", "The name of the snippet.")]

# Convert the tool properties to JSON
tool_properties_save_snippets_json = json.dumps([prop.to_dict() for prop in tool_properties_save_snippets_object])
tool_properties_get_snippets_json = json.dumps([prop.to_dict() for prop in tool_properties_get_snippets_object])


@app.function_name(name="oauth-authorization-server")
@app.route(route=".well-known/oauth-authorization-server", auth_level=func.AuthLevel.ANONYMOUS)
def oauth_authorization_server(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function oauth-authorization-server processed a request.')
    tenant_id = os.environ.get("AZURE_TENANT_ID", "common")
    base_url = f"https://login.microsoftonline.com/{tenant_id}/v2.0"
    msg = json.dumps({
        "issuer": base_url,
        "authorization_endpoint": f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/authorize",
        "token_endpoint": f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
        "jwks_uri": f"https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys",
        "response_types_supported": ["code", "id_token", "token"],
        "grant_types_supported": ["authorization_code", "client_credentials", "refresh_token"],
        "scopes_supported": ["openid", "profile", "email", "offline_access"],
        "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic", "private_key_jwt"]
    })
    return func.HttpResponse(
            msg,
            status_code=200,
            mimetype="application/json"
    )

@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="hello_mcp",
    description="Hello world.",
    toolProperties="[]",
)
def hello_mcp(context) -> None:
    """
    A simple function that returns a greeting message.

    Args:
        context: The trigger context (not used in this function).

    Returns:
        str: A greeting message.
    """
    return "Hello I am MCPTool!"


@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="list_resource_groups",
    description="list all Azure resource groups",
    toolProperties="[]",
)
def list_resource_groups(context) -> None:
    token_credential = DefaultAzureCredential()
    resource_client = ResourceManagementClient(token_credential, subscription_id)
    resource_group_list = resource_client.resource_groups.list()
    list_list = list(resource_group_list)
    print(f"System> I found {len(list_list)} resource groups")
    str_arr = []
    for resource_group in list_list:
        str_arr.append(resource_group.name)
    print(f"System> {str_arr}")
    return "\n".join(str_arr)




tool_properties_list_by_resource_group = [ToolProperty("resource_group", "string", "The name of the resoure group.")]
tool_properties_list_by_resource_group_json = json.dumps([prop.to_dict() for prop in tool_properties_list_by_resource_group])

@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="list_by_resource_group",
    description="list all Azure resources in a resource group",
    toolProperties=tool_properties_list_by_resource_group_json,
)
def list_by_resource_group(context) -> None:
    content = json.loads(context)
    resource_group = content["arguments"]["resource_group"]
    if not resource_group:
        return "no resource group specified"
    print(f"System> I am listing all the Azure resources in the resource group: {resource_group}")
    token_credential = DefaultAzureCredential()
    resource_client = ResourceManagementClient(token_credential, subscription_id)
    resource_list = resource_client.resources.list_by_resource_group(
        resource_group, expand = "createdTime,changedTime")
    list_list = list(resource_list)
    print(f"System> I found {len(list_list)} resources in the resource group {resource_group}")
    str_arr = []
    for resource in list_list:
        r_dict = {
            "name": resource.name,
            "type": resource.type.split("/")[1],
        }
        str_arr.append(f"{r_dict}")
    print(f"System> {str_arr}")
    return "\n".join(str_arr)