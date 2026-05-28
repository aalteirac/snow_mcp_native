# Native App for Snowflake Cortex Agents with External MCP Server

A Snowflake Native App that connects to an external **MCP server** and exposes all of its MCP tools to a **Cortex Agent**. Users interact with the external service through natural language via Snowflake Intelligence.

## How It Works

The app uses a single stored procedure (`internal._mcp_call`) that:

1. Authenticates to the external service via **OAuth2 client credentials** (machine token)
2. Resolves the calling Snowflake user (captured by Streamlit via `st.experimental_user`) and looks up their **external subject ID** in the `internal.user_subject_map` mapping table
3. Exchanges the M2M token for a **user-scoped token** via OAuth Token Exchange (RFC 8693), using `urn:oauth:user-impersonation` with `user_lookup.field = subject`
4. Calls the **MCP server** (`https://<tenant>/mcp`) using JSON-RPC with the user-scoped token

This means each Snowflake user calling the agent acts as their mapped external user (respecting their permissions, spaces, role-based access, etc.). Mappings are managed from the Configuration tab in the Streamlit UI.

The Cortex Agent has one generic tool (`mcp_call`) that can invoke any of the  MCP tools by name.

## Prerequisites

- **Snowflake CLI** (`snow`) installed. See https://docs.snowflake.com/en/developer-guide/snowflake-cli/index
- A configured Snowflake CLI connection profile. List yours with:
  ```bash
  snow connection list
  ```
- An **OAuth2 M2M client** with:
  - `client_credentials` grant type
  - `urn:oauth:user-impersonation` grant type (Token Exchange) **enabled**
  - Permission to access the MCP server
- **Each Snowflake user that uses the agent must be mapped to their external subject ID** (e.g. `auth0|abc123...`) in the app's User Mappings UI. Find the subject ID in the external service's Management Console > Users.

## Configuration

### 1. Makefile

Edit the `SNOWFLAKE_CONNECTION` variable in `Makefile` to match your CLI connection profile name:

```makefile
SNOWFLAKE_CONNECTION ?= MyConnectionName
```

### 2. snowflake.yml

Edit `snowflake.yml` to set your **role** and **warehouse** for deployment:

```yaml
entities:
  app_pkg:
    ...
    meta:
      role: YOUR_ROLE        # e.g. ACCOUNTADMIN or a custom role with CREATE APPLICATION PACKAGE
      warehouse: YOUR_WH     # warehouse used during deployment
  app:
    ...
    meta:
      role: YOUR_ROLE
      warehouse: YOUR_WH
```

## Deploy

```bash
make run
```

## Teardown

```bash
make teardown
```

## App Setup (Post-Install)

Once the app is installed, open the Streamlit UI and follow:

1. **Enter your tenant hostname** (e.g. `mytenant.example.com`) and click **Connect** to save it and approve the external access integration.
2. **Click "Create Agent"** to bind the procedures and create the Cortex Agent.
3. **Add User Mappings** for each Snowflake user that will use the agent: map their Snowflake username to their external subject ID (e.g. `auth0|...`). Without a mapping, calls will fail with "No subject mapping for Snowflake user".

> **IMPORTANT: An account admin must run:**
> ```sql
> GRANT CALLER USAGE ON WAREHOUSE <my_warehouse> TO APPLICATION MCP_APP;
> ```

## Available MCP Tools

The agent can call any of the 59+ tools on the MCP server, including:

| Category | Tools |
|----------|-------|
| App Discovery | `search`, `describe_app`, `get_fields`, `list_sheets` |
| Data Exploration | `get_field_values`, `search_field_values`, `get_chart_data`, `create_data_object` |
| Selections | `select_values`, `clear_selections`, `get_current_selections` |
| Visualization | `create_sheet`, `add_chart`, `add_filter` |
| Bookmarks | `list_bookmarks`, `create_bookmark`, `select_bookmark` |
| Master Items | `list_dimensions`, `create_dimension`, `list_measures`, `create_measure` |
| Datasets | `get_dataset`, `get_dataset_schema`, `get_dataset_sample` |
| Lineage | `get_lineage` |
| Glossary | `create_glossary`, `create_glossary_term`, `search_glossary_terms` |
| Data Products | `create_data_product`, `get_data_product` |

## Project Structure

```
.
├── Makefile              # CLI shortcuts (run, teardown, logs)
├── snowflake.yml         # Snow CLI project definition
├── test_auth.py          # Local OAuth test script
├── test_mcp.py           # Local MCP connection test script
└── app/
    ├── manifest.yml      # Native App manifest (references, streamlit)
    ├── README.md         # In-app documentation
    ├── streamlit/        # Streamlit UI (config + agent chat)
    │   ├── streamlit_app.py
    │   └── environment.yml
    └── sql/
        ├── init.sql      # Setup script
        ├── callbacks.sql  # Reference callbacks + tenant config
        ├── apis.sql       # Single _mcp_call procedure (OAuth + MCP JSON-RPC)
        ├── proxies.sql    # Public proxy: tools.mcp_call
        └── agent.sql      # Agent creation + run procedures
```
