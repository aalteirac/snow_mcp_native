-- =============================================================================
-- MCP Native App - Public Proxy Procedures
-- =============================================================================

-- Restricted caller's rights proc to capture the actual invoker
CREATE OR REPLACE PROCEDURE tools.get_invoker()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS RESTRICTED CALLER
AS
DECLARE
    invoker STRING;
BEGIN
    invoker := (SELECT CURRENT_USER());
    SYSTEM$LOG_INFO('get_invoker: CURRENT_USER()=' || COALESCE(invoker, 'NULL'));
    RETURN invoker;
END;

GRANT USAGE ON PROCEDURE tools.get_invoker() TO APPLICATION ROLE app_public;

-- Public proxy (owner's rights, calls RCR proc to get invoker, then internal proc)
CREATE OR REPLACE PROCEDURE tools.mcp_call(
    tool_name STRING,
    arguments STRING DEFAULT '{}'
)
RETURNS STRING
LANGUAGE SQL
AS
DECLARE
    result STRING;
    invoker STRING;
BEGIN
    CALL tools.get_invoker() INTO invoker;
    CALL internal._mcp_call(:tool_name, :arguments, :invoker) INTO result;
    RETURN result;
END;

GRANT USAGE ON PROCEDURE tools.mcp_call(STRING, STRING) TO APPLICATION ROLE app_public;
