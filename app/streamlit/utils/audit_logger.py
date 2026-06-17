"""Audit trail — writes to AUDIT schema tables. All operations are best-effort."""

import json
import uuid
import streamlit as st
from datetime import datetime, timezone
from utils.snowflake_client import get_session


def log_interaction(
    session,
    user_message: str,
    agent_response: dict,
    agent_id: str,
    user_role: str,
    data_sources: list[str] | None = None,
) -> None:
    """Registra toda interação com agente no AUDIT.PROMPT_LOG."""
    log_entry = {
        "log_id": str(uuid.uuid4()),
        "session_id": st.session_state.get("session_id", str(uuid.uuid4())),
        "user_name": session.get_current_user(),
        "role_name": user_role,
        "agent_id": agent_id,
        "prompt_text": user_message[:4000],
        "data_sources": json.dumps(data_sources or []),
        "response_summary": str(agent_response.get("content", ""))[:500],
        "cortex_tokens_used": agent_response.get("usage", {}).get("total_tokens", 0),
        "latency_ms": agent_response.get("latency_ms", 0),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        session.sql("""
            INSERT INTO AUDIT.PROMPT_LOG
            SELECT
                $1:log_id::VARCHAR,
                $1:session_id::VARCHAR,
                CURRENT_ACCOUNT(),
                $1:user_name::VARCHAR,
                $1:role_name::VARCHAR,
                $1:agent_id::VARCHAR,
                $1:prompt_text::TEXT,
                PARSE_JSON($1:data_sources::VARCHAR),
                $1:response_summary::TEXT,
                $1:cortex_tokens_used::INTEGER,
                $1:latency_ms::INTEGER,
                $1:created_at::TIMESTAMP_TZ
            FROM VALUES (PARSE_JSON(:1))
        """, params=[json.dumps(log_entry)]).collect()
    except Exception:
        pass


def log_analyst_query(
    org_id: str,
    user_name: str,
    user_role: str,
    question: str,
    sql: str | None,
    model: str,
    latency_ms: int,
    session_id: str,
) -> None:
    q = question.replace("'", "''")
    s = (sql or "").replace("'", "''")[:4000]
    try:
        get_session().sql(f"""
            INSERT INTO AUDIT.CORTEX_ANALYST_LOG
                (org_id, user_name, user_role, question, generated_sql,
                 model_used, latency_ms, session_id)
            VALUES
                ('{org_id}', '{user_name}', '{user_role}', '{q}', '{s}',
                 '{model}', {latency_ms}, '{session_id}')
        """).collect()
    except Exception:
        pass


def log_action(
    org_id: str,
    user_name: str,
    action_type: str,
    entity_type: str,
    entity_id: str,
    payload: dict | None = None,
) -> None:
    payload_str = json.dumps(payload or {}).replace("'", "''")
    try:
        get_session().sql(f"""
            INSERT INTO AUDIT.ACTION_LOG
                (org_id, user_name, action_type, entity_type, entity_id, payload)
            VALUES
                ('{org_id}', '{user_name}', '{action_type}', '{entity_type}',
                 '{entity_id}', PARSE_JSON('{payload_str}'))
        """).collect()
    except Exception:
        pass
