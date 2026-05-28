-- =============================================================================
-- MCP Native App - Reference Callbacks
-- =============================================================================

CREATE OR REPLACE PROCEDURE internal._bind_procedures()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    ALTER PROCEDURE internal._mcp_call(STRING, STRING, STRING)
        SET EXTERNAL_ACCESS_INTEGRATIONS = (reference('mcp_external_access'))
            SECRETS = ('client_id' = reference('MCP_CLIENT_ID'), 'client_secret' = reference('MCP_CLIENT_SECRET'));

    RETURN 'All procedures bound successfully';
END;

CREATE OR REPLACE PROCEDURE setup.register_reference(ref_name STRING, operation STRING, ref_or_alias STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    CASE (operation)
        WHEN 'ADD' THEN
            SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'REMOVE' THEN
            SELECT SYSTEM$REMOVE_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'CLEAR' THEN
            SELECT SYSTEM$REMOVE_ALL_REFERENCES(:ref_name);
    END CASE;

    IF (UPPER(ref_name) = 'MCP_EXTERNAL_ACCESS' AND operation = 'ADD') THEN
        CALL internal._bind_procedures();
    END IF;

    RETURN 'Reference ' || ref_name || ' ' || operation || ' completed';
END;

GRANT USAGE ON PROCEDURE setup.register_reference(STRING, STRING, STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE setup.get_configuration_for_reference(ref_name STRING)
RETURNS STRING
LANGUAGE SQL
AS
DECLARE
    tenant STRING;
BEGIN
    CASE (UPPER(ref_name))
        WHEN 'MCP_EXTERNAL_ACCESS' THEN
            SELECT value INTO tenant FROM internal.config WHERE key = 'mcp_tenant';
            IF (tenant IS NULL) THEN
                RETURN '{"type": "ERROR", "payload": {"message": "Tenant not configured. Set it in the app UI first."}}';
            END IF;
            RETURN '{"type": "CONFIGURATION", "payload": {"host_ports": ["' || tenant || ':443"], "allowed_secrets": "LIST", "secret_references": ["MCP_CLIENT_ID", "MCP_CLIENT_SECRET"]}}';
        WHEN 'MCP_CLIENT_ID' THEN
            RETURN '{"type": "CONFIGURATION", "payload": {"type": "GENERIC_STRING"}}';
        WHEN 'MCP_CLIENT_SECRET' THEN
            RETURN '{"type": "CONFIGURATION", "payload": {"type": "GENERIC_STRING"}}';
        ELSE
            RETURN '{"type": "ERROR", "payload": {"message": "Unknown reference: ' || ref_name || '"}}';
    END CASE;
END;

GRANT USAGE ON PROCEDURE setup.get_configuration_for_reference(STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.set_tenant(hostname STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    MERGE INTO internal.config AS t
    USING (SELECT 'mcp_tenant' AS key, :hostname AS value) AS s
    ON t.key = s.key
    WHEN MATCHED THEN UPDATE SET value = s.value
    WHEN NOT MATCHED THEN INSERT (key, value) VALUES (s.key, s.value);
    RETURN 'Tenant set to: ' || hostname;
END;

GRANT USAGE ON PROCEDURE tools.set_tenant(STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.set_active_user(email STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    SYSTEM$LOG_INFO('set_active_user: called with email=' || COALESCE(:email, 'NULL'));
    MERGE INTO internal.config AS t
    USING (SELECT 'active_user' AS key, :email AS value) AS s
    ON t.key = s.key
    WHEN MATCHED THEN UPDATE SET value = s.value
    WHEN NOT MATCHED THEN INSERT (key, value) VALUES (s.key, s.value);
    RETURN 'Active user set to: ' || email;
END;

GRANT USAGE ON PROCEDURE tools.set_active_user(STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.set_user_mapping(snowflake_user STRING, subject_id STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    MERGE INTO internal.user_subject_map AS t
    USING (SELECT :snowflake_user AS snowflake_user, :subject_id AS subject_id) AS s
    ON t.snowflake_user = s.snowflake_user
    WHEN MATCHED THEN UPDATE SET subject_id = s.subject_id
    WHEN NOT MATCHED THEN INSERT (snowflake_user, subject_id) VALUES (s.snowflake_user, s.subject_id);
    RETURN 'Mapping saved: ' || snowflake_user || ' -> ' || subject_id;
END;

GRANT USAGE ON PROCEDURE tools.set_user_mapping(STRING, STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.delete_user_mapping(snowflake_user STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    DELETE FROM internal.user_subject_map WHERE snowflake_user = :snowflake_user;
    RETURN 'Mapping deleted for: ' || snowflake_user;
END;

GRANT USAGE ON PROCEDURE tools.delete_user_mapping(STRING) TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE tools.list_user_mappings()
RETURNS TABLE(snowflake_user STRING, subject_id STRING)
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET res RESULTSET := (SELECT snowflake_user, subject_id FROM internal.user_subject_map ORDER BY snowflake_user);
    RETURN TABLE(res);
END;

GRANT USAGE ON PROCEDURE tools.list_user_mappings() TO APPLICATION ROLE app_public;
