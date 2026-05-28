# MCP Tools for Snowflake Cortex Agents

A Snowflake Native App that exposes an external **MCP server** as tools for a **Cortex Agent**.

## Setup

### 1. Install the app

Install from the application package. During setup you will be prompted to provide:
- **MCP_CLIENT_ID** — a `GENERIC_STRING` secret with your OAuth2 client ID
- **MCP_CLIENT_SECRET** — a `GENERIC_STRING` secret with your OAuth2 client secret

### 2. Configure in the app UI

Open the app's Streamlit interface and follow the steps:

1. **Enter your tenant hostname** (e.g. `mytenant.example.com`) and click **Connect**. This saves the tenant and prompts you to approve the external access integration.
2. Once the EAI is approved, click **Create Agent** to deploy the Cortex Agent with all MCP tools.
3. **Add User Mappings**: for each Snowflake user that will use the agent, add a mapping from their Snowflake username to their external subject ID (e.g. `auth0|abc123...`). The MCP server will execute calls under the impersonated user's permissions. The OAuth client must have the **Token Exchange** grant type enabled.

### 3. Grant warehouse access

> **IMPORTANT: An account admin must run the following before the agent can execute tools:**
>
> ```sql
> GRANT CALLER USAGE ON WAREHOUSE <my_warehouse> TO APPLICATION MCP_APP;
> ```

## Usage

Once configured, the agent appears in **Snowflake Intelligence** and can be tested from the app's **Test Agent** tab.
