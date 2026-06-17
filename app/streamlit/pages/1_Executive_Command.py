"""
NEXUS AI DataOps — Executive Command
ARR, MRR, churn trends, NPS, top opportunities, top risks.
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Executive Command · NEXUS", page_icon="📊", layout="wide")

ORG_ID = "ORG-DEMO-001"


@st.cache_data(ttl=300)
def run_query(sql: str) -> pd.DataFrame:
    return get_active_session().sql(sql).to_pandas()


st.markdown("## 📊 Executive Command")
st.caption("Visão executiva consolidada — Revenue, Clientes, Riscos e Oportunidades")
st.divider()

# ─── Revenue overview ────────────────────────────────────────────────────────

rev_df = run_query(f"""
    SELECT
        SUM(arr)                                                    AS total_arr,
        SUM(mrr)                                                    AS total_mrr,
        COUNT(*)                                                    AS total_customers,
        COUNT(CASE WHEN lifecycle_stage = 'active'  THEN 1 END)    AS active_customers,
        COUNT(CASE WHEN lifecycle_stage = 'at_risk' THEN 1 END)    AS at_risk_customers,
        COUNT(CASE WHEN lifecycle_stage = 'churned' THEN 1 END)    AS churned_customers,
        ROUND(AVG(nps_score), 1)                                   AS avg_nps,
        SUM(CASE WHEN lifecycle_stage IN ('active','at_risk') AND contract_end_date <= DATEADD('month',90,CURRENT_DATE()) THEN arr ELSE 0 END) AS renewal_90d
    FROM NEXUS_APP.CORE.CUSTOMERS
    WHERE org_id = '{ORG_ID}'
""")

r = rev_df.iloc[0]

c1, c2, c3, c4 = st.columns(4)
with c1:
    arr = r["TOTAL_ARR"] or 0
    mrr = r["TOTAL_MRR"] or 0
    st.metric("ARR Total", f"${arr / 1_000_000:.2f}M")
    st.metric("MRR Total", f"${mrr / 1_000:.0f}K")

with c2:
    st.metric("Clientes Ativos",   int(r["ACTIVE_CUSTOMERS"] or 0))
    st.metric("Clientes em Risco", int(r["AT_RISK_CUSTOMERS"] or 0), delta_color="inverse")

with c3:
    st.metric("NPS Médio",   f"{r['AVG_NPS'] or 0:.0f}")
    st.metric("Churn YTD",   int(r["CHURNED_CUSTOMERS"] or 0), delta_color="inverse")

with c4:
    renewal = r["RENEWAL_90D"] or 0
    st.metric("Renovações em 90 dias", f"${renewal / 1_000:.0f}K")

st.divider()

# ─── Top riscos ──────────────────────────────────────────────────────────────

col_risk, col_opp = st.columns(2)

with col_risk:
    st.subheader("🔴 Top Riscos")
    risk_df = run_query(f"""
        SELECT
            c.name                          AS customer,
            c.segment,
            cs.churn_probability            AS churn_prob,
            cs.expected_revenue_at_risk     AS arr_risk,
            cs.recommended_action           AS action,
            t.open_tickets
        FROM NEXUS_APP.AI.CHURN_SCORES cs
        JOIN NEXUS_APP.CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND c.org_id = cs.org_id
        LEFT JOIN (
            SELECT customer_id, COUNT(*) AS open_tickets
            FROM NEXUS_APP.CORE.TICKETS
            WHERE org_id = '{ORG_ID}' AND status = 'open'
            GROUP BY customer_id
        ) t ON cs.customer_id = t.customer_id
        WHERE cs.org_id = '{ORG_ID}'
          AND cs.risk_level = 'HIGH'
          AND cs.scored_at = (
              SELECT MAX(scored_at) FROM NEXUS_APP.AI.CHURN_SCORES
              WHERE org_id = '{ORG_ID}' AND customer_id = cs.customer_id
          )
        ORDER BY cs.churn_probability DESC
    """)

    for _, r in risk_df.iterrows():
        prob = f"{r['CHURN_PROB'] * 100:.0f}%"
        arr  = f"${r['ARR_RISK'] / 1_000:.0f}K"
        tix  = int(r["OPEN_TICKETS"] or 0)
        with st.expander(f"🔴 {r['CUSTOMER']} · Churn {prob} · ARR {arr}"):
            st.markdown(f"**Segmento:** {r['SEGMENT']}  \n**Tickets abertos:** {tix}  \n**Ação:** {r['ACTION']}")
            st.button("Escalar →", key=f"risk_esc_{r['CUSTOMER']}")


with col_opp:
    st.subheader("🟢 Top Oportunidades")
    opp_df = run_query(f"""
        SELECT
            c.name                          AS customer,
            c.segment,
            r.recommendation_type           AS type,
            r.recommendation_text           AS rec,
            r.expected_impact_usd           AS impact,
            r.confidence_score              AS confidence
        FROM NEXUS_APP.AI.RECOMMENDATIONS r
        JOIN NEXUS_APP.CORE.CUSTOMERS c
            ON r.entity_id = c.customer_id AND c.org_id = r.org_id
        WHERE r.org_id = '{ORG_ID}'
          AND r.status = 'pending'
          AND r.recommendation_type IN ('upsell', 'expansion', 'renewal')
        ORDER BY r.expected_impact_usd DESC
        LIMIT 5
    """)

    for _, r in opp_df.iterrows():
        impact = f"${r['IMPACT'] / 1_000:.0f}K"
        conf   = f"{r['CONFIDENCE'] * 100:.0f}%"
        with st.expander(f"🟢 {r['CUSTOMER']} · {r['TYPE']} · Impacto {impact}"):
            st.markdown(f"**Segmento:** {r['SEGMENT']}  \n**Confiança:** {conf}  \n{r['REC']}")
            st.button("Propor →", key=f"opp_{r['CUSTOMER']}_{r['TYPE']}")

st.divider()

# ─── Clientes por segmento ────────────────────────────────────────────────────

st.subheader("👥 Clientes por Segmento")

seg_df = run_query(f"""
    SELECT
        segment,
        COUNT(*)             AS customers,
        SUM(arr)             AS total_arr,
        ROUND(AVG(nps_score),1) AS avg_nps
    FROM NEXUS_APP.CORE.CUSTOMERS
    WHERE org_id = '{ORG_ID}' AND lifecycle_stage != 'churned'
    GROUP BY segment
    ORDER BY total_arr DESC
""")

st.dataframe(
    seg_df.rename(columns={
        "SEGMENT": "Segmento", "CUSTOMERS": "Clientes",
        "TOTAL_ARR": "ARR Total", "AVG_NPS": "NPS Médio",
    }),
    hide_index=True,
    use_container_width=True,
    column_config={"ARR Total": st.column_config.NumberColumn(format="$%.0f")},
)

st.divider()

# ─── Contratos próximos de vencer ─────────────────────────────────────────────

st.subheader("📋 Contratos — Renovações em 180 dias")

cont_df = run_query(f"""
    SELECT
        c.name                  AS customer,
        co.contract_name,
        co.contract_value,
        co.end_date,
        co.auto_renewal,
        cs.risk_level           AS churn_risk,
        DATEDIFF('day', CURRENT_DATE(), co.end_date) AS days_to_renewal
    FROM NEXUS_APP.CORE.CONTRACTS co
    JOIN NEXUS_APP.CORE.CUSTOMERS c
        ON co.customer_id = c.customer_id AND c.org_id = co.org_id
    LEFT JOIN NEXUS_APP.AI.CHURN_SCORES cs
        ON co.customer_id = cs.customer_id AND cs.org_id = co.org_id
        AND cs.scored_at = (
            SELECT MAX(scored_at) FROM NEXUS_APP.AI.CHURN_SCORES
            WHERE org_id = '{ORG_ID}' AND customer_id = co.customer_id
        )
    WHERE co.org_id = '{ORG_ID}'
      AND co.status = 'active'
      AND co.end_date <= DATEADD('day', 180, CURRENT_DATE())
    ORDER BY co.end_date ASC
""")

if cont_df.empty:
    st.info("Nenhum contrato vencendo nos próximos 180 dias.")
else:
    st.dataframe(
        cont_df.rename(columns={
            "CUSTOMER": "Cliente", "CONTRACT_NAME": "Contrato",
            "CONTRACT_VALUE": "Valor", "END_DATE": "Vencimento",
            "AUTO_RENEWAL": "Auto-Renovação", "CHURN_RISK": "Risco Churn",
            "DAYS_TO_RENEWAL": "Dias para Vencer",
        }),
        hide_index=True,
        use_container_width=True,
        column_config={"Valor": st.column_config.NumberColumn(format="$%.0f")},
    )
