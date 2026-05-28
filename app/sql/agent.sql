-- =============================================================================
-- MCP Native App - Cortex Agent (On-Demand Creation)
-- =============================================================================

CREATE OR REPLACE PROCEDURE tools.create_agent()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
AS $$
import json

def main(session):
    row = session.sql("SELECT value FROM internal.config WHERE key = 'mcp_tenant'").collect()
    if not row or not row[0][0]:
        return "ERROR: Tenant not configured. Set it in the Configuration tab first."

    spec = """models:
  orchestration: auto
instructions:
  response: "You are an assistant that uses an external MCP server. Use the mcp_call tool to interact with it. Always return clear, structured results."
  orchestration: "You have a single tool called mcp_call that connects to the external MCP server. First call mcp_call with the tools/list method to discover available tool names, then pass the tool_name and arguments JSON string to mcp_call to invoke a specific tool."
tools:
  - tool_spec:
      type: generic
      name: mcp_call
      description: "Call any tool on the external MCP server. Pass the MCP tool name and its arguments as a JSON string."
      input_schema:
        type: object
        properties:
          tool_name:
            type: string
            description: "The MCP tool name to invoke"
          arguments:
            type: string
            description: "JSON string of arguments for the tool"
        required: ["tool_name"]
tool_resources:
  mcp_call:
    identifier: tools.mcp_call
    type: procedure
    execution_environment:
      type: "warehouse"
      warehouse: ""
"""

    delim = chr(36) * 2
    create_sql = f"CREATE OR REPLACE AGENT tools.mcp_agent FROM SPECIFICATION {delim}{spec}{delim}"
    try:
        session.sql(create_sql).collect()
        session.sql("GRANT USAGE ON AGENT tools.mcp_agent TO APPLICATION ROLE app_public").collect()
        return "Agent created successfully"
    except Exception as e:
        return f"Agent creation failed: {e}"
$$;

GRANT USAGE ON PROCEDURE tools.create_agent() TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.run_agent(prompt STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
DECLARE
    agent_fqn STRING;
    request_body STRING;
    response STRING;
BEGIN
    SELECT CURRENT_DATABASE() || '.TOOLS.MCP_AGENT' INTO agent_fqn;
    request_body := '{"messages": [{"role": "user", "content": [{"type": "text", "text": "' || REPLACE(REPLACE(:prompt, '\\', '\\\\'), '"', '\\"') || '"}]}]}';
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(:agent_fqn, :request_body) INTO response;
    RETURN response;
END;

GRANT USAGE ON PROCEDURE tools.run_agent(STRING) TO APPLICATION ROLE app_public;
