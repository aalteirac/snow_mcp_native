import streamlit as st
import json
from snowflake.snowpark.context import get_active_session
import snowflake.permissions as permissions

st.set_page_config(
    page_title="MCP Agent",
    page_icon="M",
    layout="wide",
    initial_sidebar_state="collapsed"
)

st.markdown("""
<style>
    [data-testid="stAppViewBlockContainer"] {
        padding-top: 1rem;
    }
    .status-card {
        background: #ffffff;
        border: 1px solid #dee2e6;
        border-radius: 8px;
        padding: 1.25rem;
        margin-bottom: 0.75rem;
        box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    .status-ok {
        border-left: 4px solid #198754;
    }
    .status-err {
        border-left: 4px solid #dc3545;
    }
    .tool-card {
        background: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 8px;
        padding: 1rem;
        margin-bottom: 0.5rem;
    }
</style>
""", unsafe_allow_html=True)

session = get_active_session()
app_name = session.sql("SELECT CURRENT_DATABASE()").collect()[0][0]

st.markdown(f"### MCP Agent - Tool")

tab_config, tab_agent = st.tabs([
    "Configuration",
    "Test Agent"
])

# =============================================================================
# TAB 1 — Configuration
# =============================================================================
with tab_config:
    st.markdown("#### Setup")

    try:
        current_tenant = session.sql("SELECT value FROM internal.config WHERE key = 'mcp_tenant'").collect()
        current_val = current_tenant[0][0] if current_tenant else ""
    except Exception:
        current_val = ""

    eai_refs = permissions.get_reference_associations("MCP_EXTERNAL_ACCESS")
    eai_bound = len(eai_refs) > 0

    st.markdown("**Step 1** - Tenant hostname")
    tenant_input = st.text_input("Hostname", value=current_val, placeholder="mytenant.example.com", label_visibility="collapsed")

    if not eai_bound:
        if st.button("Connect", type="primary"):
            if tenant_input:
                with st.spinner("Saving and requesting access..."):
                    try:
                        session.call("tools.set_tenant", tenant_input)
                        permissions.request_reference("MCP_EXTERNAL_ACCESS")
                    except Exception as e:
                        st.error(f"Failed: {e}")
            else:
                st.warning("Enter a hostname first.")
    else:
        st.success(f"Connected to **{current_val}**")

    st.markdown("---")
    st.markdown("**Step 2** - Create the Cortex Agent")

    if eai_bound:
        if st.button("Create Agent", type="primary"):
            with st.spinner("Binding procedures and creating agent..."):
                try:
                    session.call("internal._bind_procedures")
                    result = session.call("tools.create_agent")
                    if "ERROR" in result:
                        st.error(result)
                    else:
                        st.success(result)
                except Exception as e:
                    st.error(f"Failed: {e}")
    else:
        st.info("Complete Step 1 and approve the external access integration first.")

    st.markdown("---")
    st.markdown("#### User Mappings")
    st.caption("Map Snowflake users to their external subject ID (e.g. auth0|...) to enable per-user impersonation.")

    try:
        mappings = session.sql("CALL tools.list_user_mappings()").collect()
        if mappings:
            for m in mappings:
                col_u, col_s, col_d = st.columns([2, 4, 1])
                col_u.code(m["SNOWFLAKE_USER"])
                col_s.code(m["SUBJECT_ID"])
                if col_d.button("Delete", key=f"del_{m['SNOWFLAKE_USER']}"):
                    session.call("tools.delete_user_mapping", m["SNOWFLAKE_USER"])
                    st.rerun()
        else:
            st.info("No user mappings yet. Add one below.")
    except Exception as e:
        st.error(f"Failed to load mappings: {e}")

    with st.form("add_mapping", clear_on_submit=True):
        st.markdown("**Add or update a mapping**")
        new_user = st.text_input("Snowflake username", placeholder="ANTHONY")
        new_subject = st.text_input("Subject ID", placeholder="auth0|abc123...")
        if st.form_submit_button("Save Mapping"):
            if new_user and new_subject:
                try:
                    result = session.call("tools.set_user_mapping", new_user, new_subject)
                    st.success(result)
                    st.rerun()
                except Exception as e:
                    st.error(f"Failed: {e}")
            else:
                st.warning("Both fields are required.")

# =============================================================================
# TAB 2 — Test Agent
# =============================================================================
with tab_agent:
    st.markdown("#### MCP Agent Chat")
    st.caption("Talk to the Cortex Agent that orchestrates all MCP tools.")

    if "messages" not in st.session_state:
        st.session_state.messages = []

    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    if prompt := st.chat_input("Ask something\u2026"):
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Agent is thinking..."):
                try:
                    sf_user = None
                    try:
                        sf_user = st.experimental_user.get("user_name") or st.experimental_user.get("login_name")
                    except Exception:
                        pass
                    if not sf_user:
                        sf_user = session.sql("SELECT CURRENT_USER()").collect()[0][0]
                    st.caption(f"Active user: `{sf_user}`")
                    if sf_user:
                        session.call("tools.set_active_user", sf_user)
                    raw = session.call("tools.run_agent", prompt)
                    parsed = json.loads(raw) if isinstance(raw, str) else raw
                    content_parts = parsed.get("content", [])
                    answer = ""
                    for part in content_parts:
                        if part.get("type") == "text":
                            answer += part.get("text", "")
                    if not answer:
                        answer = json.dumps(parsed, indent=2)
                    st.markdown(answer)
                    st.session_state.messages.append({"role": "assistant", "content": answer})
                except Exception as e:
                    err_msg = f"Agent error: {e}"
                    st.error(err_msg)
                    st.session_state.messages.append({"role": "assistant", "content": err_msg})
