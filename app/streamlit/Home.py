"""
NEXUS AI DataOps — Home Dashboard
Sprint 1: KPIs críticos, alertas de IA, recomendações e riscos.
"""

import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import run_query

st.set_page_config(
    page_title="NEXUS AI DataOps",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

ORG_ID = get_org_id()


# ─── Sidebar ────────────────────────────────────────────────────────────────

with st.sidebar:
    st.image("https://i.imgur.com/placeholder-nexus.png", width=140)
    st.title("NEXUS AI DataOps")
    st.caption("Enterprise AI Command Center")
    st.divider()
    st.markdown("**Organização:** ORG-DEMO-001")
    st.markdown("**Ambiente:** Production")
    st.markdown("**Modelo:** Snowflake Cortex")
    st.divider()
    st.page_link("pages/1_Executive_Command.py",    label="Executive Command",      icon="📊")
    st.page_link("pages/2_Customer_360.py",          label="Customer 360",           icon="🧑‍💼")
    st.page_link("pages/3_AI_Chat.py",               label="AI Chat",                icon="💬")
    st.page_link("pages/4_Document_Intelligence.py", label="Document Intelligence",  icon="📄")
    st.page_link("pages/5_Recommendations.py",       label="Recommendations",        icon="💡")
    st.page_link("pages/6_Data_Quality.py",          label="Data Quality",           icon="✅")
    st.page_link("pages/7_Admin.py",                 label="Admin",                  icon="⚙️")


# ─── Header ─────────────────────────────────────────────────────────────────

st.markdown("## ⚡ NEXUS AI DataOps — Home")
st.caption("Visão executiva em tempo real · Última atualização: agora")
st.divider()


# ─── KPIs críticos — via Dynamic Tables (pre-computed, refresh automático) ───

exec_df = run_query(f"""
    SELECT
        customer_count, active_count, at_risk_count,
        total_arr, arr_at_risk, avg_nps,
        open_recommendations, total_expected_impact_usd,
        avg_health_score
    FROM MART.DT_EXECUTIVE_KPIS
    WHERE org_id = '{ORG_ID}'
""")

support_df = run_query(f"""
    SELECT open_tickets, critical_tickets
    FROM AI.DT_SUPPORT_INTELLIGENCE
    WHERE org_id = '{ORG_ID}'
""")

rec_df = run_query(f"""
    SELECT COUNT(*) AS pending_recs,
           SUM(expected_impact_usd) AS total_impact
    FROM AI.RECOMMENDATIONS
    WHERE org_id = '{ORG_ID}' AND status = 'pending' AND is_active = TRUE
""")

exec_row   = exec_df.iloc[0]   if not exec_df.empty   else {}
supp_row   = support_df.iloc[0] if not support_df.empty else {}
rec_row    = rec_df.iloc[0]

col1, col2, col3, col4, col5 = st.columns(5)

with col1:
    total_arr = float(exec_row.get("TOTAL_ARR") or 0)
    st.metric("ARR Total", f"${total_arr / 1_000_000:.1f}M")

with col2:
    arr_at_risk = float(exec_row.get("ARR_AT_RISK") or 0)
    at_risk_count = int(exec_row.get("AT_RISK_COUNT") or 0)
    st.metric(
        "ARR em Risco",
        f"${arr_at_risk / 1_000:.0f}K",
        delta=f"{at_risk_count} clientes",
        delta_color="inverse",
    )

with col3:
    avg_health = float(exec_row.get("AVG_HEALTH_SCORE") or 0)
    st.metric("Health Score Médio", f"{avg_health:.0f}/100")

with col4:
    open_tickets  = int(supp_row.get("OPEN_TICKETS") or 0)
    crit_tickets  = int(supp_row.get("CRITICAL_TICKETS") or 0)
    st.metric(
        "Tickets Abertos",
        str(open_tickets),
        delta=f"{crit_tickets} críticos",
        delta_color="inverse" if crit_tickets > 0 else "off",
    )

with col5:
    nps = float(exec_row.get("AVG_NPS") or 0)
    st.metric("NPS Médio", f"{nps:.0f}", delta="±0 vs mês anterior")

st.divider()


# ─── Alertas de IA ──────────────────────────────────────────────────────────

col_left, col_right = st.columns([1.3, 1])

with col_left:
    st.subheader("🚨 Alertas de IA — Ação Imediata")

    alerts_df = run_query(f"""
        SELECT
            c.name                   AS customer,
            cs.risk_level            AS risk,
            cs.churn_probability     AS prob,
            cs.expected_revenue_at_risk AS arr_risk,
            cs.recommended_action    AS action
        FROM AI.CHURN_SCORES cs
        JOIN CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND c.org_id = cs.org_id
        WHERE cs.org_id = '{ORG_ID}'
          AND cs.risk_level IN ('HIGH', 'MEDIUM')
          AND cs.scored_at = (
              SELECT MAX(scored_at) FROM AI.CHURN_SCORES
              WHERE org_id = '{ORG_ID}' AND customer_id = cs.customer_id
          )
        ORDER BY cs.churn_probability DESC
        LIMIT 5
    """)

    for _, r in alerts_df.iterrows():
        risk_color = "🔴" if r["RISK"] == "HIGH" else "🟡"
        prob_pct = f"{r['PROB'] * 100:.0f}%"
        arr_k = f"${r['ARR_RISK'] / 1_000:.0f}K"
        with st.expander(f"{risk_color} **{r['CUSTOMER']}** — Churn {prob_pct} · ARR em risco {arr_k}"):
            st.markdown(f"**Ação recomendada:** {r['ACTION']}")
            st.button("Criar ação →", key=f"action_{r['CUSTOMER']}")


with col_right:
    st.subheader("📊 Distribuição de Risco")

    dist_df = run_query(f"""
        SELECT
            cs.risk_level,
            COUNT(*) AS count,
            SUM(cs.expected_revenue_at_risk) AS total_arr_risk
        FROM AI.CHURN_SCORES cs
        WHERE cs.org_id = '{ORG_ID}'
          AND cs.scored_at = (
              SELECT MAX(scored_at) FROM AI.CHURN_SCORES
              WHERE org_id = '{ORG_ID}' AND customer_id = cs.customer_id
          )
        GROUP BY cs.risk_level
        ORDER BY CASE cs.risk_level WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END
    """)

    st.dataframe(
        dist_df.rename(columns={
            "RISK_LEVEL": "Risco",
            "COUNT": "Clientes",
            "TOTAL_ARR_RISK": "ARR em Risco",
        }),
        hide_index=True,
        use_container_width=True,
        column_config={
            "ARR em Risco": st.column_config.NumberColumn(format="$%.0f"),
        },
    )

    st.divider()
    st.subheader("🎫 Tickets Urgentes")

    urgent_df = run_query(f"""
        SELECT
            c.name AS customer,
            t.subject,
            t.priority,
            t.sentiment_label,
            t.sla_breach
        FROM CORE.TICKETS t
        JOIN CORE.CUSTOMERS c
            ON t.customer_id = c.customer_id AND c.org_id = t.org_id
        WHERE t.org_id = '{ORG_ID}'
          AND t.status = 'open'
          AND t.priority IN ('urgent', 'high')
        ORDER BY t.sla_breach DESC, t.created_at ASC
        LIMIT 5
    """)

    st.dataframe(
        urgent_df.rename(columns={
            "CUSTOMER": "Cliente",
            "SUBJECT": "Assunto",
            "PRIORITY": "Prioridade",
            "SENTIMENT_LABEL": "Sentimento",
            "SLA_BREACH": "SLA Breach",
        }),
        hide_index=True,
        use_container_width=True,
    )

st.divider()


# ─── Recomendações pendentes ─────────────────────────────────────────────────

st.subheader("💡 Recomendações de IA — Pendentes")

pending_df = run_query(f"""
    SELECT
        c.name                  AS customer,
        r.recommendation_type   AS type,
        r.priority,
        r.recommendation_text   AS recommendation,
        r.expected_impact_usd   AS impact_usd,
        r.confidence_score      AS confidence,
        r.owner_role            AS owner
    FROM AI.RECOMMENDATIONS r
    JOIN CORE.CUSTOMERS c
        ON r.entity_id = c.customer_id AND c.org_id = r.org_id
    WHERE r.org_id = '{ORG_ID}'
      AND r.status = 'pending'
      AND r.is_active = TRUE
    ORDER BY r.priority ASC, r.expected_impact_usd DESC
""")

for _, r in pending_df.iterrows():
    priority_icon = "🔴" if r["PRIORITY"] == "HIGH" else "🟡" if r["PRIORITY"] == "MEDIUM" else "🟢"
    impact = f"${r['IMPACT_USD'] / 1_000:.0f}K"
    conf = f"{r['CONFIDENCE'] * 100:.0f}%"
    col_a, col_b = st.columns([5, 1])
    with col_a:
        st.markdown(
            f"{priority_icon} **{r['CUSTOMER']}** · `{r['TYPE']}` · Impacto estimado **{impact}** · Confiança {conf}  \n"
            f"_{r['RECOMMENDATION']}_  \n"
            f"Owner: *{r['OWNER']}*"
        )
    with col_b:
        st.button("Agir →", key=f"rec_{r['CUSTOMER']}_{r['TYPE']}")
    st.divider()


# ─── Status dos dados ────────────────────────────────────────────────────────

st.subheader("📡 Status dos Dados")

status_cols = st.columns(4)

data_status = [
    ("CORE.CUSTOMERS",    "✅ Atualizado", "10 registros",    "green"),
    ("CORE.TRANSACTIONS", "✅ Atualizado", "13 registros",    "green"),
    ("CORE.TICKETS",      "✅ Atualizado", "10 registros",    "green"),
    ("AI.CHURN_SCORES",   "✅ Atualizado", "9 scores (v1.0)", "green"),
]

for col, (table, status, detail, color) in zip(status_cols, data_status):
    with col:
        st.markdown(f"**{table}**")
        st.markdown(f":{color}[{status}]")
        st.caption(detail)
