"""NEXUS AI DataOps — Sales Intelligence (Sprint 3: + NL→SQL widget)"""

import streamlit as st
from snowflake.snowpark.context import get_active_session
from utils.cortex_analyst import render_analyst_widget

st.set_page_config(page_title="Sales Intelligence", page_icon="💰", layout="wide")

session = get_active_session()


@st.cache_data(ttl=300)
def get_revenue_opportunity_data() -> list[dict]:
    rows = session.sql("""
        SELECT
            d.customer_name,
            d.arr,
            d.churn_risk,
            d.opportunity_score,
            d.opportunity_type,
            d.estimated_revenue_usd,
            d.contract_end_date,
            d.scored_at
        FROM MART.REVENUE_OPPORTUNITY_SCORE d
        ORDER BY d.opportunity_score DESC, d.estimated_revenue_usd DESC
        LIMIT 50
    """).collect()
    return [r.as_dict() for r in rows]


@st.cache_data(ttl=300)
def get_revenue_movement() -> list[dict]:
    rows = session.sql("""
        SELECT
            month,
            transaction_type,
            transaction_count,
            total_amount
        FROM MART.DT_REVENUE_MOVEMENT
        ORDER BY month DESC
        LIMIT 24
    """).collect()
    return [r.as_dict() for r in rows]


@st.cache_data(ttl=300)
def get_pipeline_summary() -> dict:
    row = session.sql("""
        SELECT
            COUNT(*) AS total_opportunities,
            SUM(estimated_revenue_usd) AS total_pipeline,
            AVG(opportunity_score) AS avg_score,
            COUNT(CASE WHEN opportunity_type = 'upsell' THEN 1 END) AS upsell_count,
            COUNT(CASE WHEN opportunity_type = 'expansion' THEN 1 END) AS expansion_count,
            COUNT(CASE WHEN opportunity_type = 'renewal' THEN 1 END) AS renewal_count
        FROM MART.REVENUE_OPPORTUNITY_SCORE
        WHERE opportunity_score >= 0.5
    """).collect()
    return row[0].as_dict() if row else {}


st.title("Sales Intelligence")
st.caption("Pipeline de oportunidades e movimento de receita")

summary = get_pipeline_summary()

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("Pipeline Total", f"${(summary.get('TOTAL_PIPELINE') or 0):,.0f}")
with col2:
    st.metric("Oportunidades", summary.get("TOTAL_OPPORTUNITIES") or 0)
with col3:
    score = summary.get("AVG_SCORE") or 0
    st.metric("Score Médio", f"{score:.0%}")
with col4:
    renewal = summary.get("RENEWAL_COUNT") or 0
    st.metric("Renovações Pendentes", renewal)

st.divider()

tab1, tab2, tab3, tab4 = st.tabs([
    "Pipeline de Oportunidades", "Movimento de Receita", "Análise por Tipo",
    "💬 Perguntar em NL",
])

with tab1:
    opportunities = get_revenue_opportunity_data()
    if opportunities:
        import pandas as pd
        df = pd.DataFrame(opportunities)
        df.columns = [c.lower() for c in df.columns]

        type_filter = st.multiselect(
            "Filtrar por tipo",
            options=df["opportunity_type"].unique().tolist() if "opportunity_type" in df.columns else [],
            default=[],
        )
        if type_filter:
            df = df[df["opportunity_type"].isin(type_filter)]

        st.dataframe(
            df[["customer_name", "opportunity_type", "opportunity_score", "estimated_revenue_usd", "churn_risk", "arr"]].rename(columns={
                "customer_name": "Cliente",
                "opportunity_type": "Tipo",
                "opportunity_score": "Score",
                "estimated_revenue_usd": "Receita Estimada (USD)",
                "churn_risk": "Risco Churn",
                "arr": "ARR",
            }),
            use_container_width=True,
            column_config={
                "Score": st.column_config.ProgressColumn(min_value=0, max_value=1, format="%.0%"),
                "Risco Churn": st.column_config.ProgressColumn(min_value=0, max_value=1, format="%.0%"),
                "Receita Estimada (USD)": st.column_config.NumberColumn(format="$%.0f"),
                "ARR": st.column_config.NumberColumn(format="$%.0f"),
            },
        )
    else:
        st.info("Sem dados de oportunidade. Verifique se CORE.CUSTOMERS e AI.CHURN_SCORES têm dados.")

with tab2:
    movement = get_revenue_movement()
    if movement:
        import pandas as pd
        df_mv = pd.DataFrame(movement)
        df_mv.columns = [c.lower() for c in df_mv.columns]
        if "total_amount" in df_mv.columns:
            pivot = df_mv.pivot_table(
                index="month", columns="transaction_type", values="total_amount", aggfunc="sum"
            ).fillna(0)
            st.bar_chart(pivot)
        st.dataframe(df_mv, use_container_width=True)
    else:
        st.info("Sem dados de movimento de receita em CORE.TRANSACTIONS.")

with tab3:
    opportunities = get_revenue_opportunity_data()
    if opportunities:
        import pandas as pd
        df = pd.DataFrame(opportunities)
        df.columns = [c.lower() for c in df.columns]
        if "opportunity_type" in df.columns and "estimated_revenue_usd" in df.columns:
            by_type = df.groupby("opportunity_type")["estimated_revenue_usd"].sum().sort_values(ascending=False)
            st.bar_chart(by_type, horizontal=True)

            col_a, col_b, col_c = st.columns(3)
            with col_a:
                st.metric("Upsell", f"${df[df['opportunity_type']=='upsell']['estimated_revenue_usd'].sum():,.0f}")
            with col_b:
                st.metric("Expansion", f"${df[df['opportunity_type']=='expansion']['estimated_revenue_usd'].sum():,.0f}")
            with col_c:
                st.metric("Renewal", f"${df[df['opportunity_type']=='renewal']['estimated_revenue_usd'].sum():,.0f}")

with tab4:
    st.markdown("### Consulta livre — Sales Intelligence")
    st.caption("Perguntas sobre pipeline, oportunidades e movimento de receita via Cortex Analyst.")
    render_analyst_widget(
        model_file="@CORE.SEMANTIC_STAGE/revenue_opportunity_model.yaml",
        suggestions=[
            "Qual cliente tem maior score de oportunidade de upsell?",
            "Quais renovações vencem nos próximos 60 dias?",
            "Qual é o pipeline total estimado em USD?",
            "Mostre os 5 maiores scores de oportunidade.",
            "Qual o movimento de receita nos últimos 6 meses?",
            "Quais produtos estão disponíveis no catálogo?",
        ],
        key_prefix="sales_analyst",
    )
