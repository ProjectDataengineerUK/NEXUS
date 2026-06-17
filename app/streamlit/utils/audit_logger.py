"""Audit trail — writes to AUDIT schema tables. All operations are best-effort."""

import json
from utils.snowflake_client import get_session


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
            INSERT INTO AUDIT.USER_ACTIONS
                (org_id, user_name, action_type, entity_type, entity_id, payload)
            VALUES
                ('{org_id}', '{user_name}', '{action_type}', '{entity_type}',
                 '{entity_id}', PARSE_JSON('{payload_str}'))
        """).collect()
    except Exception:
        pass
