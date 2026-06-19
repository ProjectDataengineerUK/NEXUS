"""NEXUS AI DataOps — Operations Intelligence (Sprint 2 P2)"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Operations Intelligence", page_icon="⚙️", layout="wide")

session = get_active_session()


@st.cache_data(ttl=120)
def get_ticket_summary() -> dict:
    row = session.sql("""
        SELECT
            COUNT(*) AS total_open,
            COUNT(CASE WHEN priority = 'urgent' THEN 1 END) AS urgent_count,
            COUNT(CASE WHEN priority = 'high'   THEN 1 END) AS high_count,
            ROUND(AVG(DATEDIFF('hour', created_at, COALESCE(updated_at, CURRENT_TIMESTAMP()))), 1) AS avg_age_hours
        FROM CORE.TICKETS
        WHERE status = 'open'
    """).collect()
    return row[0].as_dict() if row else {}


@st.cache_data(ttl=120)
def get_tickets_by_status() -> list[dict]:
    rows = session.sql("""
        SELECT status, priority, COUNT(*) AS cnt
        FROM CORE.TICKETS
        GROUP BY status, priority
        ORDER BY cnt DESC
    """).collect()
    return [r.as_dict() for r in rows]


@st.cache_data(ttl=120)
def get_interaction_trend() -> list[dict]:
    rows = session.sql("""
        SELECT
            DATE_TRUNC('day', occurred_at) AS day,
            channel,
            COUNT(*) AS interaction_count,
            ROUND(AVG(COALESCE(sentiment_score, 0)), 2) AS avg_sentiment
        FROM CORE.INTERACTIONS
        WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
        GROUP BY DATE_TRUNC('day', occurred_at), channel
        ORDER BY day DESC
    """).collect()
    return [r.as_dict() for r in rows]


@st.cache_data(ttl=300)
def get_at_risk_with_open_tickets() -> list[dict]:
    rows = session.sql("""
        SELECT
            h.customer_id,
            h.name,
            h.churn_risk_score,
            h.risk_level,
            h.open_ticket_count,
            h.segment,
            h.arr
        FROM MART.DT_CUSTOMER_HEALTH h
        WHERE h.churn_risk_score >= 0.5
          AND h.open_ticket_count > 0
        ORDER BY h.churn_risk_score DESC, h.open_ticket_count DESC
        LIMIT 20
    """).collect()
    return [r.as_dict() for r in rows]


st.title("Operations Intelligence")
st.caption("Saúde operacional, tickets e interações com clientes")

summary = get_ticket_summary()

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("Tickets Abertos", summary.get("TOTAL_OPEN", 0))
with col2:
    urgent = summary.get("URGENT_COUNT", 0)
    st.metric("Urgente", urgent, delta=None if urgent == 0 else f"{urgent} críticos", delta_color="inverse")
with col3:
    st.metric("Prioridade Alta", summary.get("HIGH_COUNT", 0))
with col4:
    age = summary.get("AVG_AGE_HOURS", 0)
    st.metric("Idade Média (h)", f"{age:.0f}h")

st.divider()

tab1, tab2, tab3 = st.tabs(["Tickets em Risco", "Interações (30d)", "Clientes Críticos"])

with tab1:
    tickets = get_tickets_by_status()
    if tickets:
        import pandas as pd
        df = pd.DataFrame(tickets)
        df.columns = [c.lower() for c in df.columns]
        if "status" in df.columns:
            open_df = df[df["status"] == "open"] if "status" in df.columns else df
            if not open_df.empty and "priority" in open_df.columns:
                priority_counts = open_df.groupby("priority")["cnt"].sum().sort_values(ascending=False)
                st.bar_chart(priority_counts, horizontal=True)
        st.dataframe(df, use_container_width=True)
    else:
        st.info("Sem dados de tickets. Verifique CORE.TICKETS.")

with tab2:
    interactions = get_interaction_trend()
    if interactions:
        import pandas as pd
        df = pd.DataFrame(interactions)
        df.columns = [c.lower() for c in df.columns]
        if "day" in df.columns and "channel" in df.columns and "interaction_count" in df.columns:
            pivot = df.pivot_table(
                index="day", columns="channel", values="interaction_count", aggfunc="sum"
            ).fillna(0)
            st.area_chart(pivot)
            col_a, col_b = st.columns(2)
            with col_a:
                st.subheader("Por canal")
                channel_totals = df.groupby("channel")["interaction_count"].sum().sort_values(ascending=False)
                st.dataframe(channel_totals.reset_index().rename(columns={"channel": "Canal", "interaction_count": "Interações"}))
            with col_b:
                st.subheader("Sentimento médio por canal")
                if "avg_sentiment" in df.columns:
                    sentiment = df.groupby("channel")["avg_sentiment"].mean().sort_values(ascending=False)
                    st.dataframe(sentiment.reset_index().rename(columns={"channel": "Canal", "avg_sentiment": "Sentimento"}))
    else:
        st.info("Sem dados de interações. Verifique CORE.INTERACTIONS.")

with tab3:
    at_risk = get_at_risk_with_open_tickets()
    if at_risk:
        import pandas as pd
        df = pd.DataFrame(at_risk)
        df.columns = [c.lower() for c in df.columns]
        st.warning(f"⚠️ {len(df)} clientes com alto risco de churn E tickets abertos")
        st.dataframe(
            df.rename(columns={
                "name": "Cliente",
                "churn_risk_score": "Risco Churn",
                "risk_level": "Nível",
                "open_ticket_count": "Tickets Abertos",
                "segment": "Segmento",
                "arr": "ARR",
            }),
            use_container_width=True,
            column_config={
                "Risco Churn": st.column_config.ProgressColumn(min_value=0, max_value=1, format="%.0%"),
                "ARR": st.column_config.NumberColumn(format="$%.0f"),
            },
        )
    else:
        st.success("Nenhum cliente crítico com tickets abertos no momento.")

st.sidebar.subheader("Filtros")
refresh = st.sidebar.button("Atualizar dados")
if refresh:
    st.cache_data.clear()
    st.rerun()
