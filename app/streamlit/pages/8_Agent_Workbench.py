"""
NEXUS AI DataOps — Agent Workbench
Console de monitoramento, teste e avaliação dos Cortex Agents.
"""

import time

import pandas as pd
import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import call_cortex_agent as _call_agent
from utils.snowflake_client import run_query

st.set_page_config(
    page_title="Agent Workbench · NEXUS",
    page_icon="🤖",
    layout="wide",
)

ORG_ID       = get_org_id()
AGENT_MODEL  = "claude-3-5-sonnet"
SEMANTIC_MODEL = "@CORE.SEMANTIC_STAGE/nexus_revenue.yaml"
DOC_SEARCH_SVC = "AI.DOC_SEARCH"

AGENTS = {
    "executive": {
        "label": "Executive Analyst",
        "icon": "📊",
        "description": "KPIs executivos, anomalias, receita e risco geral",
        "example_questions": [
            "Qual é o ARR total e quantos clientes estão em risco?",
            "Mostre os principais KPIs executivos desta semana.",
            "Qual o impacto financeiro do churn nos próximos 90 dias?",
        ],
    },
    "revenue": {
        "label": "Revenue Agent",
        "icon": "💰",
        "description": "Forecast, pipeline, renovações e movimentos de receita",
        "example_questions": [
            "Qual o forecast de MRR para o próximo trimestre?",
            "Quais contratos vencem nos próximos 30 dias?",
            "Onde estão as maiores oportunidades de upsell?",
        ],
    },
    "customer": {
        "label": "Customer Intelligence",
        "icon": "👥",
        "description": "Customer 360, churn, health score e segmentação",
        "example_questions": [
            "Quais 10 clientes devo priorizar esta semana?",
            "Qual o health score médio por segmento?",
            "Mostre os clientes com renovação nos próximos 60 dias e risco HIGH.",
        ],
    },
    "risk": {
        "label": "Risk & Compliance",
        "icon": "🛡️",
        "description": "Riscos, SLA, anomalias de dados e segurança",
        "example_questions": [
            "Existem anomalias nos dados de clientes hoje?",
            "Quantos tickets violaram o SLA este mês?",
            "Qual o nível de risco médio da base de clientes?",
        ],
    },
    "data_steward": {
        "label": "Data Steward",
        "icon": "🗃️",
        "description": "Qualidade de dados, lineage e governança",
        "example_questions": [
            "Qual a qualidade dos dados de clientes hoje?",
            "Existem registros duplicados ou campos nulos críticos?",
            "Qual tabela teve mais atualizações nas últimas 24h?",
        ],
    },
}


def call_agent(question: str) -> dict:
    messages = [{"role": "user", "content": [{"type": "text", "text": question}]}]
    tools = [
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
                "max_results": 3,
            }
        },
    ]
    tool_resources = {
        "revenue_analyst": {"semantic_model_file": SEMANTIC_MODEL},
        "document_search": {"name": DOC_SEARCH_SVC},
    }
    return _call_agent(messages, AGENT_MODEL, tools, tool_resources)


# ─── Header ───────────────────────────────────────────────────────────────────

st.title("🤖 Agent Workbench")
st.caption("Monitore, teste e avalie os Cortex Agents do NEXUS AI DataOps.")

# ─── Seção 1: Status dos Agentes ──────────────────────────────────────────────

st.header("Status dos Agentes", divider="gray")

try:
    stats = run_query(f"""
        SELECT
            COUNT_IF(started_at >= CURRENT_DATE())                        AS sessions_today,
            SUM(CASE WHEN started_at >= CURRENT_DATE() THEN message_count ELSE 0 END) AS messages_today,
            ROUND(AVG(NULLIF(total_tokens, 0)), 0)                        AS avg_tokens
        FROM NEXUS_APP.AI.AGENT_SESSIONS
        WHERE org_id = '{ORG_ID}'
    """)

    c1, c2, c3 = st.columns(3)
    c1.metric("Sessões hoje",    int(stats["SESSIONS_TODAY"].iloc[0] or 0))
    c2.metric("Mensagens hoje",  int(stats["MESSAGES_TODAY"].iloc[0] or 0))
    c3.metric("Tokens médios/sessão", int(stats["AVG_TOKENS"].iloc[0] or 0))
except Exception:
    st.info("Ainda não há sessões de agente registradas.")

st.subheader("Agentes disponíveis")
cols = st.columns(len(AGENTS))
for col, (agent_id, info) in zip(cols, AGENTS.items()):
    with col:
        st.markdown(f"**{info['icon']} {info['label']}**")
        st.caption(info["description"])
        try:
            cnt = run_query(f"""
                SELECT COUNT(*) AS n
                FROM NEXUS_APP.AI.AGENT_SESSIONS
                WHERE org_id = '{ORG_ID}' AND agent_id = '{agent_id}'
                  AND started_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
            """)
            n = int(cnt["N"].iloc[0] or 0)
            st.caption(f"🟢 {n} sessões (7d)")
        except Exception:
            st.caption("🟡 sem dados")

st.divider()

# ─── Seção 2: Teste de Agente ─────────────────────────────────────────────────

st.header("Testar Agente", divider="gray")

agent_key = st.selectbox(
    "Escolha o agente:",
    options=list(AGENTS.keys()),
    format_func=lambda k: f"{AGENTS[k]['icon']} {AGENTS[k]['label']}",
)
selected = AGENTS[agent_key]

st.caption(f"💡 {selected['description']}")

st.markdown("**Perguntas de exemplo:**")
example_cols = st.columns(len(selected["example_questions"]))
chosen_example = None
for col, q in zip(example_cols, selected["example_questions"]):
    if col.button(q[:60] + ("…" if len(q) > 60 else ""), key=f"ex_{q[:20]}", use_container_width=True):
        chosen_example = q

question = st.text_area(
    "Pergunta:",
    value=chosen_example or "",
    height=80,
    placeholder="Digite sua pergunta para o agente...",
    key="agent_question",
)

if st.button("▶ Testar Agente", type="primary", disabled=not question.strip()):
    with st.spinner(f"Consultando {selected['label']}..."):
        t0 = time.time()
        result = call_agent(question.strip())
        latency = int((time.time() - t0) * 1000)

    col_resp, col_meta = st.columns([3, 1])
    with col_resp:
        if result.get("error"):
            st.error(f"Erro: {result['error']}")
        else:
            st.markdown("**Resposta:**")
            st.markdown(result.get("text") or "_Sem resposta textual._")

    with col_meta:
        st.metric("Latência", f"{latency} ms")
        if result.get("tool_calls"):
            with st.expander("Tool calls"):
                st.json(result["tool_calls"])

st.divider()

# ─── Seção 3: Histórico de Sessões ────────────────────────────────────────────

st.header("Histórico de Sessões", divider="gray")

try:
    sessions = run_query(f"""
        SELECT session_id, agent_id, user_name, user_role,
               TO_CHAR(started_at, 'YYYY-MM-DD HH24:MI') AS started_at,
               message_count, total_tokens
        FROM NEXUS_APP.AI.AGENT_SESSIONS
        WHERE org_id = '{ORG_ID}'
        ORDER BY started_at DESC
        LIMIT 20
    """)

    if sessions.empty:
        st.info("Nenhuma sessão registrada ainda.")
    else:
        st.dataframe(sessions, use_container_width=True, hide_index=True)

        session_id = st.selectbox(
            "Ver mensagens da sessão:",
            options=sessions["SESSION_ID"].tolist(),
            format_func=lambda s: f"{s[:8]}… — {sessions[sessions['SESSION_ID']==s]['AGENT_ID'].values[0]}",
        )
        if st.button("Ver mensagens"):
            msgs = run_query(f"""
                SELECT role, LEFT(content, 300) AS content_preview,
                       TO_CHAR(created_at, 'HH24:MI:SS') AS time
                FROM NEXUS_APP.AI.AGENT_MESSAGES
                WHERE session_id = '{session_id}'
                ORDER BY created_at
            """)
            st.dataframe(msgs, use_container_width=True, hide_index=True)

except Exception as e:
    st.warning(f"Não foi possível carregar o histórico: {e}")

st.divider()

# ─── Seção 4: Avaliação Rápida ────────────────────────────────────────────────

st.header("Avaliação Rápida", divider="gray")
st.caption("Executa as perguntas de exemplo de cada agente e verifica se retornam resposta.")

agents_to_eval = st.multiselect(
    "Agentes para avaliar:",
    options=list(AGENTS.keys()),
    default=["executive"],
    format_func=lambda k: f"{AGENTS[k]['icon']} {AGENTS[k]['label']}",
)

if st.button("▶ Rodar Avaliação", disabled=not agents_to_eval):
    total_pass = total_fail = 0

    for agent_key in agents_to_eval:
        info = AGENTS[agent_key]
        st.subheader(f"{info['icon']} {info['label']}")

        rows = []
        for q in info["example_questions"]:
            t0 = time.time()
            res = call_agent(q)
            lat = int((time.time() - t0) * 1000)
            passed = bool(res.get("text") and not res.get("error"))
            status = "✅ PASS" if passed else "❌ FAIL"
            if passed:
                total_pass += 1
            else:
                total_fail += 1
            rows.append({"Pergunta": q[:80], "Status": status, "Latência (ms)": lat})

        st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)

    st.success(f"Avaliação concluída: **{total_pass} PASS** / **{total_fail} FAIL**")
