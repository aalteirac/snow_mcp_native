-- =============================================================================
-- MCP Native App - Setup Script
-- =============================================================================

CREATE APPLICATION ROLE IF NOT EXISTS app_public;

CREATE OR ALTER SCHEMA setup;
GRANT USAGE ON SCHEMA setup TO APPLICATION ROLE app_public;

CREATE OR ALTER SCHEMA tools;
GRANT USAGE ON SCHEMA tools TO APPLICATION ROLE app_public;

CREATE OR ALTER SCHEMA internal;

CREATE TABLE IF NOT EXISTS internal.config (
    key STRING PRIMARY KEY,
    value STRING
);

CREATE TABLE IF NOT EXISTS internal.user_subject_map (
    snowflake_user STRING PRIMARY KEY,
    subject_id STRING
);

-- GRANT USAGE ON SCHEMA internal TO APPLICATION ROLE app_public;
-- GRANT SELECT ON TABLE internal.config TO APPLICATION ROLE app_public;

EXECUTE IMMEDIATE FROM './callbacks.sql';
EXECUTE IMMEDIATE FROM './apis.sql';
EXECUTE IMMEDIATE FROM './proxies.sql';
EXECUTE IMMEDIATE FROM './agent.sql';


CREATE OR REPLACE PROCEDURE setup.version_init()
RETURNS STRING LANGUAGE SQL
AS $$
BEGIN
    BEGIN
        CALL internal._bind_procedures();
    EXCEPTION WHEN OTHER THEN
        RETURN 'Bind skipped (references not yet set)';
    END;
    RETURN 'DONE';
END;
$$;

-- =============================================================================
-- STREAMLIT APP
-- =============================================================================

CREATE OR REPLACE STREAMLIT tools.mcp_agent_ui
    FROM '/streamlit'
    MAIN_FILE = 'streamlit_app.py';

GRANT USAGE ON STREAMLIT tools.mcp_agent_ui TO APPLICATION ROLE app_public;
