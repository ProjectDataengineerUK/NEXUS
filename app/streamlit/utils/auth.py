"""Resolve user identity and org context from the active Snowflake session."""

import streamlit as st
from snowflake.snowpark.context import get_active_session


@st.cache_data(ttl=300)
def get_current_user() -> str:
    return get_active_session().sql("SELECT CURRENT_USER()").collect()[0][0]


@st.cache_data(ttl=300)
def get_current_role() -> str:
    return get_active_session().sql("SELECT CURRENT_ROLE()").collect()[0][0]


@st.cache_data(ttl=300)
def get_org_id() -> str:
    """Resolve org_id from APP_CONFIG; falls back to demo org for local dev."""
    try:
        rows = get_active_session().sql(
            "SELECT config_value FROM CORE.APP_CONFIG WHERE config_key = 'org_id' LIMIT 1"
        ).collect()
        if rows:
            return rows[0][0]
    except Exception:
        pass
    return "ORG-DEMO-001"


def get_context() -> dict:
    """Returns {org_id, user_name, user_role} for the current request."""
    return {
        "org_id": get_org_id(),
        "user_name": get_current_user(),
        "user_role": get_current_role(),
    }
