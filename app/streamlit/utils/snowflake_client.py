"""Snowflake session, query helpers, and Cortex API wrappers."""

import json
import time

import pandas as pd
import requests
import streamlit as st
from snowflake.snowpark.context import get_active_session


@st.cache_resource
def get_session():
    return get_active_session()


def run_query(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


execute_query = run_query


def run_sql(sql: str) -> list:
    return get_session().sql(sql).collect()


# ─── REST helpers ─────────────────────────────────────────────────────────────

def _rest_headers() -> tuple[str, dict]:
    session = get_session()
    token = session.connection.rest.token
    host = session.connection.host
    return host, {
        "Authorization": f'Snowflake Token="{token}"',
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


# ─── Cortex Analyst ───────────────────────────────────────────────────────────

def call_cortex_analyst(question: str, semantic_model: str) -> dict:
    """Calls Cortex Analyst REST API. Returns {sql, text, error, latency_ms}."""
    host, headers = _rest_headers()
    url = f"https://{host}/api/v2/cortex/analyst/message"
    payload = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_model_file": semantic_model,
    }
    t0 = time.time()
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=60)
        latency_ms = int((time.time() - t0) * 1000)
        resp.raise_for_status()
        result = {"sql": None, "text": None, "error": None, "latency_ms": latency_ms}
        for item in resp.json().get("message", {}).get("content", []):
            if item["type"] == "sql":
                result["sql"] = item["statement"]
            elif item["type"] == "text":
                result["text"] = item.get("text", "")
        return result
    except Exception as e:
        return {"sql": None, "text": None, "error": str(e), "latency_ms": 0}


# ─── Cortex Agent ─────────────────────────────────────────────────────────────

def call_cortex_agent(
    messages: list[dict],
    model: str,
    tools: list[dict],
    tool_resources: dict,
) -> dict:
    """Calls Cortex Agents REST API (SSE streaming). Returns {text, tool_calls, error}."""
    host, headers = _rest_headers()
    url = f"https://{host}/api/v2/cortex/agent:run"
    payload = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "tool_resources": tool_resources,
    }
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=90)
        resp.raise_for_status()
        full_text, tool_calls = "", []
        for line in resp.text.splitlines():
            if not line.startswith("data:"):
                continue
            chunk = json.loads(line[5:].strip())
            delta = chunk.get("choices", [{}])[0].get("delta", {})
            for item in delta.get("content", []):
                if item.get("type") == "text":
                    full_text += item.get("text", "")
                elif item.get("type") == "tool_use":
                    tool_calls.append(item)
        return {"text": full_text, "tool_calls": tool_calls, "error": None}
    except Exception as e:
        return {"text": None, "tool_calls": [], "error": str(e)}


# ─── Cortex Search ────────────────────────────────────────────────────────────

def cortex_search(
    query: str,
    service: str,
    columns: list[str],
    limit: int = 5,
    doc_filter: str | None = None,
) -> list[dict]:
    """Executes semantic search via SNOWFLAKE.CORTEX.SEARCH_PREVIEW."""
    filter_clause = ""
    if doc_filter:
        filter_clause = f', "filter": {{"@eq": {{"document_id": "{doc_filter}"}}}}'

    safe_query = query.replace('"', "").replace("'", "")
    cols_json = json.dumps(columns)

    sql = f"""
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                '{service}',
                '{{
                    "query":   "{safe_query}",
                    "columns": {cols_json},
                    "limit":   {limit}
                    {filter_clause}
                }}'
            )
        ) AS results
    """
    rows = get_session().sql(sql).collect()
    if not rows:
        return []
    raw = rows[0]["RESULTS"]
    if isinstance(raw, str):
        raw = json.loads(raw)
    return raw.get("results", [])


# ─── Cortex Complete ──────────────────────────────────────────────────────────

def cortex_complete(prompt: str, model: str) -> str:
    """Calls SNOWFLAKE.CORTEX.COMPLETE and returns the generated text."""
    safe = prompt.replace("'", "\\'").replace("\\n", " ")
    rows = get_session().sql(
        f"SELECT SNOWFLAKE.CORTEX.COMPLETE('{model}', '{safe}') AS answer"
    ).collect()
    return rows[0]["ANSWER"] if rows else ""
