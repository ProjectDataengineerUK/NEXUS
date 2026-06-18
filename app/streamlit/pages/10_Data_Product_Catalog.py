"""
NEXUS AI DataOps — Data Product Catalog
Inventário de data products, tabelas, modelos e serviços disponíveis no ambiente.
"""

import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import run_query

st.set_page_config(
    page_title="Data Product Catalog · NEXUS",
    page_icon="🗂️",
    layout="wide",
)

ORG_ID = get_org_id()

DOMAIN_ICON = {
    "CUSTOMER":   "👥",
    "FINANCIAL":  "💰",
    "OPERATIONAL":"⚙️",
    "AI_OUTPUT":  "🤖",
    "AUDIT":      "🔐",
    "SYSTEM":     "🖥️",
}

TYPE_ICON = {
    "table":          "🗃️",
    "view":           "👁️",
    "dynamic_table":  "⚡",
    "cortex_search":  "🔍",
    "semantic_model": "📐",
    "ml_model":       "🧠",
    "pipeline":       "🔄",
}

# ─── Catálogo estático dos data products NEXUS ────────────────────────────────
# Em produção, isso viria de INFORMATION_SCHEMA + tags + lineage do Horizon Catalog.

CATALOG = [
    # ── MART layer ────────────────────────────────────────────────────────────
    {
        "name":        "MART.CUSTOMER_360",
        "type":        "view",
        "domain":      "CUSTOMER",
        "sla":         "2h",
        "owner":       "Data Engineering",
        "description": "Visão unificada 360° de cada cliente: health score, ARR, churn risk, próxima renovação.",
        "columns":     "customer_id, customer_name, segment, health_score, churn_risk_level, arr_usd, renewal_date, …",
        "consumers":   ["2_Customer_360.py", "Agent Customer Intelligence", "Cortex Analyst"],
        "pii":         True,
    },
    {
        "name":        "MART.EXECUTIVE_KPIS_RT",
        "type":        "dynamic_table",
        "domain":      "FINANCIAL",
        "sla":         "2h",
        "owner":       "Data Engineering",
        "description": "KPIs executivos em near-real-time: ARR, MRR, NRR, churn rate, clientes em risco.",
        "columns":     "org_id, total_arr, total_mrr, churn_rate, customers_at_risk, …",
        "consumers":   ["1_Executive_Command.py", "Agent Executive Analyst"],
        "pii":         False,
    },
    {
        "name":        "MART.FEATURE_USAGE_RT",
        "type":        "dynamic_table",
        "domain":      "OPERATIONAL",
        "sla":         "1h",
        "owner":       "Data Engineering",
        "description": "Adoção de features por cliente e hora, alimentado por Snowpipe Streaming.",
        "columns":     "org_id, customer_id, event_hour, event_type, event_count, unique_users, …",
        "consumers":   ["2_Customer_360.py", "Recommendation Engine"],
        "pii":         False,
    },
    {
        "name":        "MART.API_COST_RT",
        "type":        "dynamic_table",
        "domain":      "OPERATIONAL",
        "sla":         "2h",
        "owner":       "Platform Engineering",
        "description": "Consumo de tokens LLM e custo estimado por organização e modelo.",
        "columns":     "org_id, usage_date, model_name, api_calls, total_tokens, estimated_cost_usd, …",
        "consumers":   ["7_Admin.py"],
        "pii":         False,
    },
    # ── AI layer ──────────────────────────────────────────────────────────────
    {
        "name":        "AI.CHURN_SCORES",
        "type":        "table",
        "domain":      "AI_OUTPUT",
        "sla":         "24h",
        "owner":       "Data Science",
        "description": "Score de churn (0-1) por cliente, atualizado diariamente por modelo XGBoost.",
        "columns":     "customer_id, org_id, churn_probability, risk_level, scored_at, model_version, …",
        "consumers":   ["MART.CUSTOMER_360", "5_Recommendations.py", "Agent Customer"],
        "pii":         False,
    },
    {
        "name":        "AI.RECOMMENDATIONS",
        "type":        "table",
        "domain":      "AI_OUTPUT",
        "sla":         "12h",
        "owner":       "Data Science",
        "description": "Recomendações acionáveis geradas por LLM: retenção, upsell, SLA, engajamento.",
        "columns":     "recommendation_id, org_id, entity_id, recommendation_type, priority, expected_impact_usd, …",
        "consumers":   ["5_Recommendations.py", "9_Action_Center.py"],
        "pii":         False,
    },
    {
        "name":        "AI.EXECUTIVE_BRIEFINGS",
        "type":        "table",
        "domain":      "AI_OUTPUT",
        "sla":         "24h",
        "owner":       "Data Science",
        "description": "Briefings executivos diários/semanais gerados automaticamente via Cortex.",
        "columns":     "briefing_id, org_id, briefing_type, content, generated_at, …",
        "consumers":   ["1_Executive_Command.py"],
        "pii":         False,
    },
    {
        "name":        "AI.V_CONTRACT_INTELLIGENCE",
        "type":        "view",
        "domain":      "FINANCIAL",
        "sla":         "4h",
        "owner":       "Data Engineering",
        "description": "Inteligência de contratos com cláusulas extraídas por AI, datas de vencimento e flags de risco.",
        "columns":     "document_id, contract_name, customer_name, contract_value_usd, end_date, renewal_status, risk_flags, …",
        "consumers":   ["4_Document_Intelligence.py", "Agent Risk & Compliance"],
        "pii":         True,
    },
    # ── Cortex Search ─────────────────────────────────────────────────────────
    {
        "name":        "AI.DOC_SEARCH",
        "type":        "cortex_search",
        "domain":      "OPERATIONAL",
        "sla":         "30min",
        "owner":       "Platform Engineering",
        "description": "Busca semântica em todos os documentos indexados: contratos, SLAs, relatórios, políticas.",
        "columns":     "chunk_text, document_name, document_type, section_title, …",
        "consumers":   ["3_AI_Chat.py", "4_Document_Intelligence.py", "Cortex Agents"],
        "pii":         True,
    },
    {
        "name":        "AI.CONTRACT_SEARCH",
        "type":        "cortex_search",
        "domain":      "FINANCIAL",
        "sla":         "1h",
        "owner":       "Platform Engineering",
        "description": "Busca semântica dedicada a contratos: cláusulas, penalidades, SLAs, renovações.",
        "columns":     "chunk_text, contract_name, customer_name, contract_type, end_date, …",
        "consumers":   ["4_Document_Intelligence.py", "Agent Risk & Compliance"],
        "pii":         True,
    },
    # ── Semantic Models ────────────────────────────────────────────────────────
    {
        "name":        "nexus_revenue.yaml",
        "type":        "semantic_model",
        "domain":      "FINANCIAL",
        "sla":         "—",
        "owner":       "Analytics Engineering",
        "description": "Modelo semântico de receita para Cortex Analyst: ARR, MRR, churn, forecast.",
        "columns":     "dimensions: customer, segment, date | metrics: arr, mrr, nrr, churn_rate",
        "consumers":   ["3_AI_Chat.py", "Cortex Analyst", "Cortex Agents"],
        "pii":         False,
    },
    {
        "name":        "customer_360.yaml",
        "type":        "semantic_model",
        "domain":      "CUSTOMER",
        "sla":         "—",
        "owner":       "Analytics Engineering",
        "description": "Modelo semântico Customer 360 para Cortex Analyst: saúde, risco, contratos.",
        "columns":     "dimensions: customer, segment, risk_level | metrics: health_score, arr, tickets",
        "consumers":   ["3_AI_Chat.py", "Agent Customer Intelligence"],
        "pii":         False,
    },
    # ── ML Models ─────────────────────────────────────────────────────────────
    {
        "name":        "CHURN_RISK_CLASSIFIER",
        "type":        "ml_model",
        "domain":      "AI_OUTPUT",
        "sla":         "24h",
        "owner":       "Data Science",
        "description": "XGBoost v1.0.0 — probabilidade de churn em 30 dias. AUC ~0.87.",
        "columns":     "input: 42 features | output: churn_probability (0-1), risk_level",
        "consumers":   ["AI.CHURN_SCORES"],
        "pii":         False,
    },
    {
        "name":        "REVENUE_FORECAST_MODEL",
        "type":        "ml_model",
        "domain":      "FINANCIAL",
        "sla":         "24h",
        "owner":       "Data Science",
        "description": "Prophet + XGBoost ensemble — forecast MRR 90 dias. MAPE < 8%.",
        "columns":     "input: historical MRR + features | output: mrr_forecast, confidence_interval",
        "consumers":   ["1_Executive_Command.py", "Agent Revenue"],
        "pii":         False,
    },
    # ── Pipelines ─────────────────────────────────────────────────────────────
    {
        "name":        "PIPE_PRODUCT_EVENTS",
        "type":        "pipeline",
        "domain":      "OPERATIONAL",
        "sla":         "real-time",
        "owner":       "Platform Engineering",
        "description": "Snowpipe Streaming — ingestão contínua de eventos de produto (cliques, features, APIs).",
        "columns":     "event_id, org_id, customer_id, event_type, event_payload, server_ts",
        "consumers":   ["MART.FEATURE_USAGE_RT"],
        "pii":         False,
    },
]


# ─── Header ───────────────────────────────────────────────────────────────────

st.title("🗂️ Data Product Catalog")
st.caption("Inventário de tabelas, views, modelos, serviços de busca e pipelines do NEXUS AI DataOps.")

# ─── Métricas ─────────────────────────────────────────────────────────────────

c1, c2, c3, c4 = st.columns(4)
c1.metric("Data Products", len(CATALOG))
c2.metric("Com SLA real-time / 1h", sum(1 for p in CATALOG if p["sla"] in ("real-time", "1h", "30min")))
c3.metric("Com PII", sum(1 for p in CATALOG if p["pii"]))
c4.metric("Tipos distintos", len({p["type"] for p in CATALOG}))

st.divider()

# ─── Filtros ──────────────────────────────────────────────────────────────────

col_f1, col_f2, col_f3 = st.columns(3)
with col_f1:
    domains = sorted({p["domain"] for p in CATALOG})
    sel_domains = st.multiselect("Domínio", domains, default=domains)
with col_f2:
    types = sorted({p["type"] for p in CATALOG})
    sel_types = st.multiselect("Tipo", types, default=types,
                               format_func=lambda t: f"{TYPE_ICON.get(t,'📦')} {t}")
with col_f3:
    search_term = st.text_input("Buscar por nome ou descrição", placeholder="customer, churn, contract…")

filtered = [
    p for p in CATALOG
    if p["domain"] in sel_domains
    and p["type"] in sel_types
    and (not search_term or search_term.lower() in p["name"].lower() or search_term.lower() in p["description"].lower())
]

st.caption(f"{len(filtered)} de {len(CATALOG)} data products")
st.divider()

# ─── Cards ────────────────────────────────────────────────────────────────────

for product in filtered:
    icon     = TYPE_ICON.get(product["type"], "📦")
    d_icon   = DOMAIN_ICON.get(product["domain"], "🔷")
    pii_flag = " 🔒 PII" if product["pii"] else ""

    with st.expander(
        f"{icon} **{product['name']}**  ·  {d_icon} {product['domain']}"
        f"  ·  SLA `{product['sla']}`{pii_flag}",
        expanded=False,
    ):
        col_l, col_r = st.columns([3, 1])
        with col_l:
            st.markdown(f"**Descrição:** {product['description']}")
            st.markdown(f"**Colunas:** `{product['columns']}`")
            st.markdown("**Consumidores:** " + "  ·  ".join(f"`{c}`" for c in product["consumers"]))
        with col_r:
            st.caption(f"**Tipo:** {product['type']}")
            st.caption(f"**Owner:** {product['owner']}")
            st.caption(f"**SLA:** {product['sla']}")
            if product["pii"]:
                st.warning("Contém PII", icon="🔒")

# ─── Seção: Lineage ───────────────────────────────────────────────────────────

st.divider()
st.subheader("Lineage simplificado")
st.caption("Fluxo de dados de ponta a ponta — da ingestão até os consumidores.")

lineage_md = """
```
Fontes Externas                    RAW (Snowpipe Streaming)
  Salesforce CRM  ──────────────▶  RAW.PRODUCT_EVENTS
  Zendesk Tickets ──────────────▶  RAW.API_USAGE_EVENTS
  Stripe Billing  ──────┐
  Fivetran / COPY  ─────┘
                         │
                         ▼
                    CORE (Bronze)
              CUSTOMERS · SUBSCRIPTIONS · TICKETS · DOCUMENTS
                         │
                         ▼
              Transformações dbt (Silver → Gold)
         stg_customers · stg_tickets · fct_revenue · dim_customer
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
         MART (Gold)           AI LAYER
      CUSTOMER_360           CHURN_SCORES
      EXECUTIVE_KPIS_RT      RECOMMENDATIONS
      FEATURE_USAGE_RT       EXECUTIVE_BRIEFINGS
      API_COST_RT            V_CONTRACT_INTELLIGENCE
              │                     │
              └──────────┬──────────┘
                         ▼
              Cortex Search / Semantic Models
         AI.DOC_SEARCH · AI.CONTRACT_SEARCH
         nexus_revenue.yaml · customer_360.yaml
                         │
                         ▼
                 Cortex Agents & UI
           Executive · Customer · Revenue · Risk · Data Steward
```
"""
st.markdown(lineage_md)

# ─── Qualidade dos data products ─────────────────────────────────────────────

st.divider()
st.subheader("Qualidade (Data Metric Functions)")

try:
    dmf_df = run_query("""
        SELECT
            measurement_time,
            table_name,
            metric_name,
            value
        FROM SNOWFLAKE.LOCAL.DATA_METRIC_FUNCTION_REFERENCES
        WHERE table_database = 'NEXUS_APP'
        ORDER BY measurement_time DESC
        LIMIT 50
    """)
    if not dmf_df.empty:
        st.dataframe(dmf_df, use_container_width=True, hide_index=True)
    else:
        st.info("Métricas de qualidade ainda não disponíveis. Execute os Data Metric Functions em `18_data_metric_functions.sql`.")
except Exception:
    st.info("Métricas de qualidade serão exibidas aqui após configuração dos Data Metric Functions.")
