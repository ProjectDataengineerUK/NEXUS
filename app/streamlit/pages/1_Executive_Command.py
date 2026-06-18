"""
NEXUS AI DataOps — Executive Command
ARR, MRR, churn trends, NPS, top opportunities, top risks.
"""

import streamlit as st
import pandas as pd
from utils.snowflake_client import run_query
from utils.auth import get_org_id

st.set_page_config(page_title="Executive Command · NEXUS", page_icon="📊", layout="wide")

ORG_ID = get_org_id()


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
    FROM CORE.CUSTOMERS
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
        FROM AI.CHURN_SCORES cs
        JOIN CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND c.org_id = cs.org_id
        LEFT JOIN (
            SELECT customer_id, COUNT(*) AS open_tickets
            FROM CORE.TICKETS
            WHERE org_id = '{ORG_ID}' AND status = 'open'
            GROUP BY customer_id
        ) t ON cs.customer_id = t.customer_id
        WHERE cs.org_id = '{ORG_ID}'
          AND cs.risk_level = 'HIGH'
          AND cs.scored_at = (
              SELECT MAX(scored_at) FROM AI.CHURN_SCORES
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
        FROM AI.RECOMMENDATIONS r
        JOIN CORE.CUSTOMERS c
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
    FROM CORE.CUSTOMERS
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
    FROM CORE.CONTRACTS co
    JOIN CORE.CUSTOMERS c
        ON co.customer_id = c.customer_id AND c.org_id = co.org_id
    LEFT JOIN AI.CHURN_SCORES cs
        ON co.customer_id = cs.customer_id AND cs.org_id = co.org_id
        AND cs.scored_at = (
            SELECT MAX(scored_at) FROM AI.CHURN_SCORES
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

st.divider()

# ─── Scenario Simulation (What-If) ───────────────────────────────────────────

st.markdown("## 🔮 Scenario Simulation — What-If")
st.caption("Simule o impacto de intervenções de retenção e upsell no ARR e na base ativa.")

sim_col1, sim_col2 = st.columns(2)

with sim_col1:
    st.subheader("Retenção de Churn")
    churn_reduction_pct = st.slider(
        "% de clientes em risco HIGH que seriam retidos",
        min_value=0, max_value=100, value=50, step=5,
        help="Se sua equipe intervier em X% dos casos de alto risco, qual o impacto no ARR?"
    )
    avg_arr_at_risk = st.number_input(
        "ARR médio do cliente em risco (USD)",
        min_value=1000, max_value=5_000_000, value=50_000, step=1000,
    )

    try:
        at_risk_count = int(run_query(f"""
            SELECT COUNT(*) AS n FROM NEXUS_APP.MART.CUSTOMER_360
            WHERE org_id = '{ORG_ID}' AND churn_risk_level = 'HIGH'
        """)["N"].iloc[0] or 0)
    except Exception:
        at_risk_count = 10

    retained = round(at_risk_count * churn_reduction_pct / 100)
    arr_saved = retained * avg_arr_at_risk

    st.metric("Clientes HIGH em risco",  at_risk_count)
    st.metric("Clientes retidos (estimado)", retained)
    st.metric("ARR preservado (estimado)", f"${arr_saved:,.0f}", delta=f"+${arr_saved:,.0f}")

with sim_col2:
    st.subheader("Expansão de Receita (Upsell)")
    upsell_pct = st.slider(
        "% de clientes com upsell bem-sucedido",
        min_value=0, max_value=50, value=15, step=5,
        help="Qual % da base atual converteria para um plano superior?"
    )
    avg_upsell_value = st.number_input(
        "Incremento médio de ARR por upsell (USD)",
        min_value=500, max_value=200_000, value=12_000, step=500,
    )

    try:
        active_count = int(run_query(f"""
            SELECT COUNT(*) AS n FROM NEXUS_APP.MART.CUSTOMER_360
            WHERE org_id = '{ORG_ID}' AND lifecycle_stage = 'active'
        """)["N"].iloc[0] or 0)
    except Exception:
        active_count = 50

    upsold = round(active_count * upsell_pct / 100)
    arr_expansion = upsold * avg_upsell_value

    st.metric("Clientes ativos", active_count)
    st.metric("Upsells projetados", upsold)
    st.metric("Expansão ARR (estimada)", f"${arr_expansion:,.0f}", delta=f"+${arr_expansion:,.0f}")

# Resumo combinado
st.divider()
total_impact = arr_saved + arr_expansion
st.markdown(f"### Impacto total estimado: **${total_impact:,.0f}** ARR")
st.caption(f"= ${arr_saved:,.0f} retido (churn) + ${arr_expansion:,.0f} expandido (upsell)")

if st.button("📝 Gerar análise detalhada com IA", type="primary"):
    with st.spinner("Gerando análise de cenário…"):
        try:
            analysis = run_query(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE(
                    'claude-3-5-sonnet',
                    ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
                        'role', 'user',
                        'content', 'Você é um CFO advisor. Analise este cenário de negócios: ' ||
                            '{at_risk_count} clientes em alto risco de churn, ARR médio de ${avg_arr_at_risk:,}. ' ||
                            'Se {churn_reduction_pct}% forem retidos, economizamos ${arr_saved:,}. ' ||
                            'Adicionalmente, {upsell_pct}% da base de {active_count} clientes ativos seria upsold, ' ||
                            'gerando ${arr_expansion:,} de expansão. ' ||
                            'Forneça: 1) Avaliação da viabilidade, 2) Principais riscos, ' ||
                            '3) Ações prioritárias recomendadas. Máximo 200 palavras em português.'
                    ))
                ) AS analysis
            """)
            st.markdown(analysis["ANALYSIS"].iloc[0])
        except Exception as e:
            st.warning(f"Análise não disponível: {e}")
