"""
NEXUS AI DataOps — AI Chat
Sprint 4: Cortex Analyst (NL→SQL), Executive Agent (multi-tool), perguntas sugeridas.
"""

import json
import time
import uuid
import requests
import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="AI Chat · NEXUS",
    page_icon="💬",
    layout="wide",
)

ORG_ID            = "ORG-DEMO-001"
SEMANTIC_MODEL    = "@NEXUS_APP.CORE.SEMANTIC_STAGE/nexus_revenue.yaml"
DOC_SEARCH_SVC    = "NEXUS_APP.AI.DOC_SEARCH"
ANALYST_MODEL     = "mistral-large2"
AGENT_MODEL       = "claude-3-5-sonnet"


# ─── Helpers ──────────────────────────────────────────────────────────────────

@st.cache_resource
def get_session():
    return get_active_session()


def run_sql(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


def _snowflake_headers() -> tuple[str, dict]:
    """Retorna (host, headers) para chamadas REST à API Snowflake."""
    session = get_session()
    token   = session.connection.rest.token
    host    = session.connection.host
    headers = {
        "Authorization": f'Snowflake Token="{token}"',
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    return host, headers


def call_cortex_analyst(question: str) -> dict:
    """Chama Cortex Analyst REST API — retorna {sql, text, error}."""
    host, headers = _snowflake_headers()
    url = f"https://{host}/api/v2/cortex/analyst/message"

    payload = {
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]}
        ],
        "semantic_model_file": SEMANTIC_MODEL,
    }

    t0  = time.time()
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=60)
        latency_ms = int((time.time() - t0) * 1000)
        resp.raise_for_status()
        data = resp.json()

        result = {"sql": None, "text": None, "error": None, "latency_ms": latency_ms}

        for item in data.get("message", {}).get("content", []):
            if item["type"] == "sql":
                result["sql"] = item["statement"]
            elif item["type"] == "text":
                result["text"] = item.get("text", "")

        return result

    except Exception as e:
        return {"sql": None, "text": None, "error": str(e), "latency_ms": 0}


def call_cortex_agent(messages: list[dict]) -> dict:
    """Chama Cortex Agents REST API — retorna {text, tool_calls, error}."""
    host, headers = _snowflake_headers()
    url = f"https://{host}/api/v2/cortex/agent:run"

    payload = {
        "model": AGENT_MODEL,
        "messages": messages,
        "tools": [
            {
                "tool_spec": {
                    "type": "cortex_analyst_text_to_sql",
                    "name": "revenue_analyst",
                    "semantic_model_file": SEMANTIC_MODEL,
                }
            },
            {
                "tool_spec": {
                    "type": "cortex_search",
                    "name": "document_search",
                    "service_name": DOC_SEARCH_SVC,
                    "max_results": 4,
                }
            },
        ],
        "tool_resources": {
            "revenue_analyst": {"semantic_model_file": SEMANTIC_MODEL},
            "document_search": {"name": DOC_SEARCH_SVC},
        },
    }

    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=90)
        resp.raise_for_status()

        full_text  = ""
        tool_calls = []

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


def log_query(question: str, sql: str | None, latency_ms: int, session_id: str):
    """Persiste query no audit log (best-effort)."""
    try:
        q = question.replace("'", "''")
        s = (sql or "").replace("'", "''")[:4000]
        run_sql(f"""
            INSERT INTO NEXUS_APP.AUDIT.CORTEX_ANALYST_LOG
                (org_id, user_name, user_role, question, generated_sql,
                 model_used, latency_ms, session_id)
            VALUES
                ('{ORG_ID}', CURRENT_USER(), CURRENT_ROLE(), '{q}', '{s}',
                 '{ANALYST_MODEL}', {latency_ms}, '{session_id}')
        """)
    except Exception:
        pass


def auto_chart(df: pd.DataFrame, question: str):
    """Tenta gerar um gráfico automático baseado na estrutura do DataFrame."""
    if df.empty or len(df.columns) < 2:
        return

    num_cols  = df.select_dtypes(include="number").columns.tolist()
    cat_cols  = df.select_dtypes(exclude="number").columns.tolist()

    if not num_cols:
        return

    keywords_bar  = ["por segmento", "por região", "por indústria", "ranking",
                     "top", "comparar", "comparativo"]
    keywords_line = ["tendência", "trend", "histórico", "ao longo", "por mês", "por dia"]

    q_lower = question.lower()

    if any(k in q_lower for k in keywords_line) and len(num_cols) >= 1:
        date_cols = [c for c in df.columns if "date" in c.lower() or "month" in c.lower()]
        if date_cols:
            st.line_chart(df.set_index(date_cols[0])[num_cols[:3]])
            return

    if cat_cols and len(df) <= 20:
        chart_df = df.set_index(cat_cols[0])[num_cols[0]]
        st.bar_chart(chart_df)


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("💬 AI Chat")
    st.divider()

    chat_mode = st.radio(
        "Modo",
        ["🧠 Executive Agent", "📊 Cortex Analyst"],
        help=(
            "**Executive Agent** — multi-tool: responde com dados E documentos.  \n"
            "**Cortex Analyst** — foco em dados estruturados, gera SQL explicável."
        ),
    )

    st.divider()
    st.caption("Executive Agent usa `claude-3-5-sonnet` com Cortex Analyst + Cortex Search.")
    st.caption("Cortex Analyst usa `mistral-large2` com semantic model NEXUS Revenue.")
    st.divider()
    st.page_link("Home.py", label="← Home", icon="⚡")
    st.page_link("pages/4_Document_Intelligence.py", label="📄 Document Intelligence")

# ─── Estado de sessão ────────────────────────────────────────────────────────

if "analyst_history" not in st.session_state:
    st.session_state.analyst_history = []
if "agent_history" not in st.session_state:
    st.session_state.agent_history = []
if "chat_session_id" not in st.session_state:
    st.session_state.chat_session_id = str(uuid.uuid4())


# ═════════════════════════════════════════════════════════════════════════════
# MODO: Cortex Analyst
# ═════════════════════════════════════════════════════════════════════════════

if chat_mode == "📊 Cortex Analyst":
    st.markdown("## 📊 Cortex Analyst — Dados em Linguagem Natural")
    st.caption(
        "Faça perguntas sobre receita, clientes e churn. "
        "O Analyst gera SQL a partir do semantic model e executa automaticamente."
    )

    ANALYST_SUGGESTIONS = [
        "Qual é o ARR total por segmento de clientes?",
        "Quais clientes têm risco de churn HIGH?",
        "Qual é o health score médio por região?",
        "Quais renovações vencem nos próximos 90 dias?",
        "Qual é o total de ARR em risco de cancelamento?",
        "Mostre os 5 clientes com maior receita em risco.",
    ]

    with st.expander("💡 Perguntas sugeridas", expanded=not st.session_state.analyst_history):
        cols = st.columns(3)
        for i, sug in enumerate(ANALYST_SUGGESTIONS):
            if cols[i % 3].button(sug, key=f"asug_{i}"):
                st.session_state.analyst_history.append({"role": "user", "content": sug})
                st.rerun()

    # Histórico
    for msg in st.session_state.analyst_history:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("df") is not None and not msg["df"].empty:
                st.dataframe(msg["df"], hide_index=True, use_container_width=True)
                auto_chart(msg["df"], msg["content"])
            if msg.get("sql"):
                with st.expander("🔍 SQL gerado"):
                    st.code(msg["sql"], language="sql")
            if msg.get("latency_ms"):
                st.caption(f"⚡ {msg['latency_ms']}ms")

    if question := st.chat_input("Pergunte sobre clientes, receita ou churn…"):
        st.session_state.analyst_history.append({"role": "user", "content": question})

        with st.chat_message("user"):
            st.markdown(question)

        with st.chat_message("assistant"):
            with st.spinner("Gerando SQL e executando consulta…"):
                result = call_cortex_analyst(question)

            if result["error"]:
                st.error(f"Erro no Cortex Analyst: {result['error']}")
                response_entry = {"role": "assistant", "content": f"❌ {result['error']}"}

            else:
                # Executa SQL gerado
                df = pd.DataFrame()
                if result["sql"]:
                    try:
                        df = run_sql(result["sql"])
                    except Exception as e:
                        st.warning(f"SQL gerado mas falhou ao executar: {e}")

                # Monta resposta textual
                answer_text = result["text"] or ""
                if df is not None and not df.empty:
                    st.markdown(answer_text or f"Encontrei **{len(df)} resultados**:")
                    st.dataframe(df, hide_index=True, use_container_width=True)
                    auto_chart(df, question)
                else:
                    st.markdown(answer_text or "Nenhum resultado encontrado.")
                    df = pd.DataFrame()

                if result["sql"]:
                    with st.expander("🔍 SQL gerado pelo Cortex Analyst"):
                        st.code(result["sql"], language="sql")

                st.caption(f"⚡ {result['latency_ms']}ms · Modelo: `{ANALYST_MODEL}`")

                log_query(question, result["sql"], result["latency_ms"],
                          st.session_state.chat_session_id)

                response_entry = {
                    "role": "assistant",
                    "content": answer_text or f"{len(df)} resultados encontrados.",
                    "sql": result["sql"],
                    "df": df if not df.empty else None,
                    "latency_ms": result["latency_ms"],
                }

        st.session_state.analyst_history.append(response_entry)

    if st.session_state.analyst_history:
        if st.button("🗑️ Limpar conversa", key="clear_analyst"):
            st.session_state.analyst_history = []
            st.rerun()


# ═════════════════════════════════════════════════════════════════════════════
# MODO: Executive Agent
# ═════════════════════════════════════════════════════════════════════════════

else:
    st.markdown("## 🧠 Executive Agent")
    st.caption(
        "Agente multi-tool com acesso a dados estruturados **e** documentos corporativos. "
        "Responde perguntas complexas que cruzam contratos, métricas e clientes."
    )

    AGENT_SUGGESTIONS = [
        "Qual cliente está em maior risco? Tem alguma cláusula de penalidade no contrato dele?",
        "Quais renovações vencem esse trimestre e o que dizem os SLAs sobre isso?",
        "Qual é o impacto financeiro total se todos os clientes HIGH churn cancelarem?",
        "Compare o health score dos clientes ENTERPRISE com os MID_MARKET.",
        "Quais clientes têm SLA breach E risco de churn ao mesmo tempo?",
    ]

    with st.expander("💡 Perguntas sugeridas", expanded=not st.session_state.agent_history):
        for i, sug in enumerate(AGENT_SUGGESTIONS):
            if st.button(sug, key=f"agsug_{i}"):
                st.session_state.agent_history.append({"role": "user", "content": sug})
                st.rerun()

    # Histórico
    for msg in st.session_state.agent_history:
        if msg["role"] == "tool":
            continue
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("tool_calls"):
                with st.expander(f"🔧 {len(msg['tool_calls'])} ferramenta(s) usada(s)"):
                    for tc in msg["tool_calls"]:
                        st.caption(f"**{tc.get('name','tool')}**")

    if question := st.chat_input("Pergunte sobre clientes, documentos ou estratégia…"):
        st.session_state.agent_history.append({"role": "user", "content": question})

        with st.chat_message("user"):
            st.markdown(question)

        with st.chat_message("assistant"):
            with st.spinner("Agente processando… consultando dados e documentos…"):
                # Monta payload de mensagens para o agente
                agent_messages = [
                    {
                        "role": "system",
                        "content": (
                            "Você é o Executive AI Agent da NEXUS AI DataOps. "
                            "Responda com dados precisos, cite fontes e termine com uma recomendação de ação. "
                            f"Organização atual: {ORG_ID}. "
                            "Use os dados disponíveis — não invente números."
                        ),
                    }
                ]
                for m in st.session_state.agent_history:
                    if m["role"] in ("user", "assistant") and m.get("content"):
                        agent_messages.append({"role": m["role"], "content": m["content"]})

                result = call_cortex_agent(agent_messages)

            if result["error"]:
                st.error(f"Erro no Executive Agent: {result['error']}")
                answer = f"❌ {result['error']}"
                tool_calls = []
            else:
                answer = result["text"] or "Sem resposta gerada."
                tool_calls = result["tool_calls"]

                st.markdown(answer)

                if tool_calls:
                    tools_used = [tc.get("name","tool") for tc in tool_calls]
                    st.caption(f"🔧 Ferramentas: {', '.join(set(tools_used))} · Modelo: `{AGENT_MODEL}`")

        st.session_state.agent_history.append({
            "role": "assistant",
            "content": answer,
            "tool_calls": tool_calls,
        })

    if st.session_state.agent_history:
        if st.button("🗑️ Limpar conversa", key="clear_agent"):
            st.session_state.agent_history = []
            st.rerun()
