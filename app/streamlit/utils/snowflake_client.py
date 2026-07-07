"""Snowflake session, query helpers, and Cortex API wrappers."""

import json
import time

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

try:
    import _snowflake
except ImportError:
    _snowflake = None


@st.cache_resource
def get_session():
    return get_active_session()


def run_query(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


execute_query = run_query


def run_sql(sql: str) -> list:
    return get_session().sql(sql).collect()


@st.cache_data(ttl=600)
def cortex_search_service_exists(service_name: str) -> bool:
    """Checks if a Cortex Search Service exists.

    Contas trial/certas regiões podem não ter acesso à função de embedding
    do Cortex Search — nesse caso a criação do serviço no setup_script.sql
    é pulada tolerantemente (ver comentário lá) e o serviço nunca existe.
    Usado para montar tool lists de Cortex Agents sem referenciar um serviço
    inexistente, o que faria a chamada inteira falhar.
    """
    if "." not in service_name:
        return False
    schema, name = service_name.rsplit(".", 1)
    try:
        rows = get_session().sql(
            f"SHOW CORTEX SEARCH SERVICES LIKE '{name}' IN SCHEMA {schema}"
        ).collect()
        return len(rows) > 0
    except Exception:
        return False


# ─── REST helpers ─────────────────────────────────────────────────────────────
#
# Streamlit rodando DENTRO do Snowflake (Native App/Streamlit-in-Snowflake) não
# tem `session.connection.rest.token` (o objeto de conexão nesse runtime é um
# StoredProcRestful, sem esse atributo — isso só existe numa sessão externa do
# Python Connector). A forma correta e documentada de chamar as REST APIs do
# Cortex a partir de dentro do Snowflake é via `_snowflake.send_snow_api_request`,
# conforme o app de exemplo oficial da Snowflake para Cortex Analyst em
# Streamlit-in-Snowflake (sfguide-getting-started-with-cortex-analyst).

def _snow_api_request(path: str, body: dict, timeout_ms: int = 60000) -> dict:
    """POST autenticado a uma REST API do Snowflake via ponte interna (_snowflake)."""
    resp = _snowflake.send_snow_api_request(
        "POST", path, {}, {}, body, None, timeout_ms,
    )
    content = json.loads(resp["content"]) if resp.get("content") else {}
    return {"status": resp["status"], "content": content}


# ─── Cortex Analyst ───────────────────────────────────────────────────────────

def call_cortex_analyst(question: str, semantic_model: str) -> dict:
    """Calls Cortex Analyst REST API. Returns {sql, text, error, latency_ms}."""
    payload = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_model_file": semantic_model,
    }
    t0 = time.time()
    try:
        resp = _snow_api_request("/api/v2/cortex/analyst/message", payload)
        latency_ms = int((time.time() - t0) * 1000)
        if resp["status"] >= 400:
            msg = resp["content"].get("message", f"HTTP {resp['status']}")
            return {"sql": None, "text": None, "error": msg, "latency_ms": latency_ms}
        result = {"sql": None, "text": None, "error": None, "latency_ms": latency_ms}
        for item in resp["content"].get("message", {}).get("content", []):
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
    """Calls Cortex Agents REST API. Returns {text, tool_calls, error}."""
    payload = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "tool_resources": tool_resources,
    }
    try:
        resp = _snow_api_request("/api/v2/cortex/agent:run", payload, timeout_ms=90000)
        if resp["status"] >= 400:
            msg = resp["content"].get("message", f"HTTP {resp['status']}")
            return {"text": None, "tool_calls": [], "error": msg}

        full_text, tool_calls = "", []
        content = resp["content"]
        # A resposta pode vir como um único objeto (não-streaming) com
        # choices[0].message, ou como lista de chunks SSE já decodificados.
        chunks = content if isinstance(content, list) else [content]
        for chunk in chunks:
            choice = (chunk.get("choices") or [{}])[0]
            delta = choice.get("delta") or choice.get("message") or {}
            for item in delta.get("content", []) or []:
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
    try:
        rows = get_session().sql(sql).collect()
    except Exception as exc:
        # Cortex Search pode não estar disponível na conta (trial/região) —
        # mesma classe de restrição já tratada no setup_script.sql para a
        # criação do serviço. Degrada graciosamente em vez de derrubar a página.
        st.warning(f"⚠️ Cortex Search indisponível nesta conta: {exc}")
        return []
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
