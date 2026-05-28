-- =============================================================================
-- MCP Native App - MCP Call Procedure (with User Impersonation)
-- =============================================================================

CREATE OR REPLACE PROCEDURE internal._mcp_call(
    tool_name STRING,
    arguments STRING,
    invoker_user STRING
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('requests', 'snowflake-snowpark-python')
HANDLER = 'main'
AS $$
import _snowflake
import requests
import json
import logging

logger = logging.getLogger("mcp")

def get_tenant(session):
    logger.info("get_tenant: reading mcp_tenant from internal.config")
    row = session.sql("SELECT value FROM internal.config WHERE key = 'mcp_tenant'").collect()
    if not row or not row[0][0]:
        logger.warning("get_tenant: mcp_tenant not configured")
        raise Exception("Tenant not configured. Set it in the app UI first.")
    tenant = row[0][0].strip()
    logger.info(f"get_tenant: resolved tenant={tenant}")
    return tenant

def get_user_subject(session, sf_user):
    logger.info(f"get_user_subject: invoker_user={sf_user}")

    # If invoker_user is None (agent context), read active_user from config (set by Streamlit)
    if not sf_user:
        row = session.sql("SELECT value FROM internal.config WHERE key = 'active_user'").collect()
        if row and row[0][0]:
            sf_user = row[0][0].strip()
            logger.info(f"get_user_subject: read active_user from config={sf_user}")

    if not sf_user:
        logger.error("get_user_subject: no Snowflake user available (neither invoker nor active_user)")
        raise Exception("No Snowflake user identified. Open the app via Streamlit so it can capture your identity.")

    # Look up the subject ID in the mapping table
    row = session.sql(f"SELECT subject_id FROM internal.user_subject_map WHERE snowflake_user = '{sf_user}'").collect()
    if row and row[0][0]:
        subject = row[0][0].strip()
        logger.info(f"get_user_subject: mapped {sf_user} -> {subject}")
        return subject

    logger.error(f"get_user_subject: no mapping found for Snowflake user '{sf_user}'")
    raise Exception(f"No subject mapping for Snowflake user '{sf_user}'. Add a mapping in the app UI.")

def get_m2m_token(tenant, client_id, client_secret):
    token_url = f"https://{tenant}/oauth/token"
    logger.info(f"get_m2m_token: POST {token_url} grant_type=client_credentials")
    resp = requests.post(token_url, json={
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret
    }, headers={"Content-Type": "application/json"}, timeout=30)
    logger.info(f"get_m2m_token: status={resp.status_code}")
    if resp.status_code != 200:
        logger.error(f"get_m2m_token: failed body={resp.text[:500]}")
    resp.raise_for_status()
    token = resp.json()["access_token"]
    logger.info("get_m2m_token: token acquired")
    return token

def get_user_token(tenant, client_id, client_secret, subject):
    token_url = f"https://{tenant}/oauth/token"
    logger.info(f"get_user_token: POST {token_url} grant_type=user-impersonation user_lookup.subject={subject}")
    resp = requests.post(token_url, json={
        "grant_type": "urn:oauth:user-impersonation",
        "client_id": client_id,
        "client_secret": client_secret,
        "user_lookup": {"field": "subject", "value": subject}
    }, headers={"Content-Type": "application/json"}, timeout=30)
    logger.info(f"get_user_token: status={resp.status_code}")
    if resp.status_code != 200:
        logger.error(f"get_user_token: failed body={resp.text[:500]}")
    resp.raise_for_status()
    token = resp.json()["access_token"]
    logger.info(f"get_user_token: user-scoped token acquired for subject={subject}")
    return token

def mcp_post(mcp_url, headers, payload):
    method_name = payload.get("method", "?")
    logger.info(f"mcp_post: POST {mcp_url} method={method_name}")
    resp = requests.post(mcp_url, headers=headers, json=payload, stream=True, timeout=180)
    logger.info(f"mcp_post: status={resp.status_code} method={method_name}")
    if resp.status_code != 200:
        logger.error(f"mcp_post: failed body={resp.text[:500]}")
    resp.raise_for_status()
    session_id = resp.headers.get("Mcp-Session-Id")

    result = None
    for line in resp.iter_lines(decode_unicode=True):
        if line and line.startswith("data:"):
            data = line[5:].strip()
            if data:
                try:
                    result = json.loads(data)
                except json.JSONDecodeError:
                    pass

    if result is None:
        try:
            result = json.loads(resp.text)
        except:
            result = {"raw": resp.text[:2000]}

    return result, session_id

def main(session, tool_name: str, arguments=None, invoker_user=None) -> str:
    logger.info(f"_mcp_call: tool_name={tool_name} invoker_user={invoker_user}")

    step = "init"
    try:
        step = "get_tenant"
        tenant = get_tenant(session)

        step = "read_secrets"
        logger.info("read_secrets: reading client_id from secret")
        client_id = _snowflake.get_generic_secret_string('client_id').strip()
        logger.info(f"read_secrets: got client_id (len={len(client_id)})")
        logger.info("read_secrets: reading client_secret from secret")
        client_secret = _snowflake.get_generic_secret_string('client_secret').strip()
        logger.info(f"read_secrets: got client_secret (len={len(client_secret)})")

        step = "get_user_subject"
        subject = get_user_subject(session, invoker_user)

        step = "get_user_token"
        token = get_user_token(tenant, client_id, client_secret, subject)
    except requests.exceptions.HTTPError as e:
        return json.dumps({"error": f"[{step}] {e}", "response": e.response.text[:1000] if e.response else ""})
    except Exception as e:
        return json.dumps({"error": f"[{step}] {str(e)}"})

    mcp_url = f"https://{tenant}/api/ai/mcp"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": f"Bearer {token}"
    }

    try:
        step = "mcp_initialize"
        init_payload = {
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "snowflake-native-app", "version": "1.0"}
            },
            "id": 1
        }
        init_result, session_id = mcp_post(mcp_url, headers, init_payload)

        if isinstance(init_result, dict) and "error" in init_result:
            return json.dumps({"error": f"[{step}] MCP initialize failed", "detail": init_result.get("error")})

        if session_id:
            headers["Mcp-Session-Id"] = session_id

        step = "parse_arguments"
        if arguments is None or arguments == "" or arguments == "null":
            args = {}
        elif isinstance(arguments, dict):
            args = arguments
        elif isinstance(arguments, str):
            try:
                args = json.loads(arguments)
            except (json.JSONDecodeError, TypeError):
                args = {}
        else:
            args = {}

        step = f"tools/call:{tool_name}"
        call_payload = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": args},
            "id": 2
        }
        result, _ = mcp_post(mcp_url, headers, call_payload)

        if isinstance(result, dict):
            if "result" in result:
                return json.dumps(result["result"], indent=2)
            elif "error" in result:
                return json.dumps({"error": f"[{step}] {result['error']}"}, indent=2)

        return json.dumps(result, indent=2)
    except requests.exceptions.HTTPError as e:
        return json.dumps({"error": f"[{step}] HTTP {e}", "response": e.response.text[:500] if e.response else ""})
    except Exception as e:
        return json.dumps({"error": f"[{step}] {str(e)}"})
$$;
