"""
NEXUS AI DataOps — Customer 360
Sprint 2: ARR, usage trend, ticket count, sentiment, renewal date, churn score.
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Customer 360 · NEXUS",
    page_icon="🧑‍💼",
    layout="wide",
)

ORG_ID = "ORG-DEMO-001"


@st.cache_data(ttl=300)
def run_query(sql: str) -> pd.DataFrame:
    return get_active_session().sql(sql).to_pandas()


def health_color(score: float) -> str:
    if score >= 75:
        return "green"
    if score >= 50:
        return "orange"
    return "red"


def risk_icon(level: str) -> str:
    return {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}.get(level, "⚪")


def trend_icon(trend: str) -> str:
    return {"up": "📈", "down": "📉", "stable": "➡️", "no_data": "❓"}.get(trend, "❓")


def sentiment_icon(label: str) -> str:
    return {"positive": "😊", "negative": "😟", "neutral": "😐"}.get(label, "❓")


# ─── Sidebar — seleção de cliente ────────────────────────────────────────────

with st.sidebar:
    st.title("🧑‍💼 Customer 360")
    st.divider()

    customers_df = run_query(f"""
        SELECT customer_id, name, segment, lifecycle_stage
        FROM NEXUS_APP.MART.CUSTOMER_360
        WHERE org_id = '{ORG_ID}'
        ORDER BY arr DESC NULLS LAST
    """)

    customer_options = {
        f"{r['NAME']} ({r['SEGMENT']})" : r["CUSTOMER_ID"]
        for _, r in customers_df.iterrows()
    }

    selected_label = st.selectbox(
        "Selecionar cliente",
        options=list(customer_options.keys()),
    )
    selected_id = customer_options[selected_label]

    st.divider()
    st.caption("Dados atualizados a cada hora via Dynamic Table.")
    st.page_link("Home.py", label="← Voltar ao Home", icon="⚡")


# ─── Carregar dados do cliente ────────────────────────────────────────────────

c360 = run_query(f"""
    SELECT * FROM NEXUS_APP.MART.CUSTOMER_360
    WHERE org_id = '{ORG_ID}' AND customer_id = '{selected_id}'
""")

if c360.empty:
    st.error("Cliente não encontrado na visão Customer 360.")
    st.stop()

r = c360.iloc[0]

# ─── Cabeçalho ────────────────────────────────────────────────────────────────

col_title, col_badge = st.columns([5, 1])
with col_title:
    st.markdown(f"## 🧑‍💼 {r['CUSTOMER_NAME']}")
    st.caption(
        f"{r['INDUSTRY']} · {r['REGION']} · `{r['SEGMENT']}` · "
        f"Cliente desde {str(r['CUSTOMER_SINCE'])[:10]}"
    )
with col_badge:
    health = float(r["HEALTH_SCORE"] or 0)
    color  = health_color(health)
    st.markdown(f"### Health Score")
    st.markdown(f"**:{color}[{health:.0f} / 100]**")

st.divider()

# ─── KPIs principais ──────────────────────────────────────────────────────────

k1, k2, k3, k4, k5, k6 = st.columns(6)

with k1:
    arr = float(r["ARR"] or 0)
    st.metric("ARR", f"${arr / 1_000:.0f}K")

with k2:
    mrr = float(r["MRR"] or 0)
    st.metric("MRR", f"${mrr / 1_000:.0f}K")

with k3:
    prob = float(r["CHURN_PROBABILITY"] or 0)
    level = str(r["CHURN_RISK_LEVEL"] or "—")
    st.metric(
        "Churn Score",
        f"{prob * 100:.0f}%",
        delta=f"{risk_icon(level)} {level}",
        delta_color="off",
    )

with k4:
    nps = r["NPS_SCORE"]
    st.metric("NPS", f"{int(nps)}" if nps is not None else "—")

with k5:
    open_t = int(r["OPEN_TICKETS"] or 0)
    crit   = int(r["CRITICAL_OPEN_TICKETS"] or 0)
    st.metric(
        "Tickets Abertos",
        str(open_t),
        delta=f"{crit} críticos" if crit else "0 críticos",
        delta_color="inverse" if crit > 0 else "off",
    )

with k6:
    renewal = r["NEAREST_RENEWAL_DATE"]
    renewal_str = str(renewal)[:10] if renewal else "—"
    days_str = ""
    if renewal:
        import datetime
        renewal_date = pd.to_datetime(renewal).date()
        days_left = (renewal_date - datetime.date.today()).days
        days_str = f"{days_left}d"
    st.metric("Renovação", renewal_str, delta=days_str if days_str else None)

st.divider()

# ─── Duas colunas: Uso + Tickets ─────────────────────────────────────────────

col_uso, col_tickets = st.columns(2)

with col_uso:
    st.subheader(f"📊 Uso do Produto {trend_icon(str(r['USAGE_TREND']))}")

    u1, u2, u3 = st.columns(3)
    with u1:
        st.metric("Eventos (30d)", int(r["EVENTS_30D"] or 0))
    with u2:
        st.metric("Dias ativos (30d)", int(r["ACTIVE_DAYS_30D"] or 0))
    with u3:
        st.metric("Features usadas", int(r["DISTINCT_FEATURES_USED"] or 0))

    st.caption(f"Últimos 7 dias: **{int(r['EVENTS_7D'] or 0)} eventos** · {int(r['ACTIVE_DAYS_7D'] or 0)} dias ativos")

    last_act = r["LAST_ACTIVITY_AT"]
    days_ago = int(r["DAYS_SINCE_LAST_ACTIVITY"] or 0)
    if last_act:
        st.caption(f"Última atividade: {str(last_act)[:16]} ({days_ago} dias atrás)")
    else:
        st.warning("Nenhuma atividade registrada nos últimos 30 dias.")

    if int(r["AGENT_INVOCATIONS_30D"] or 0) > 0:
        st.success(f"🤖 {int(r['AGENT_INVOCATIONS_30D'])} invocações de agente IA no último mês.")

    st.divider()
    st.subheader("📅 Timeline de eventos recentes")

    events_df = run_query(f"""
        SELECT
            DATE(occurred_at)   AS day,
            event_type,
            feature_name,
            COUNT(*)            AS count
        FROM NEXUS_APP.CORE.PRODUCT_EVENTS
        WHERE org_id = '{ORG_ID}'
          AND customer_id = '{selected_id}'
          AND occurred_at >= DATEADD('day', -14, CURRENT_TIMESTAMP())
        GROUP BY 1, 2, 3
        ORDER BY day DESC
        LIMIT 20
    """)

    if events_df.empty:
        st.info("Nenhum evento nos últimos 14 dias.")
    else:
        st.dataframe(
            events_df.rename(columns={
                "DAY": "Data", "EVENT_TYPE": "Tipo",
                "FEATURE_NAME": "Feature", "COUNT": "Ocorrências",
            }),
            hide_index=True,
            use_container_width=True,
        )


with col_tickets:
    sentiment = str(r["SENTIMENT_LABEL"] or "neutral")
    avg_sent  = r["AVG_SENTIMENT_SCORE"]
    avg_sent_str = f"{float(avg_sent):.2f}" if avg_sent is not None else "—"

    st.subheader(f"🎫 Tickets {sentiment_icon(sentiment)}")

    t1, t2, t3 = st.columns(3)
    with t1:
        st.metric("Total", int(r["TOTAL_TICKETS"] or 0))
    with t2:
        st.metric("Abertos", int(r["OPEN_TICKETS"] or 0))
    with t3:
        st.metric("SLA Breach", int(r["SLA_BREACHES"] or 0), delta_color="inverse")

    st.caption(f"Sentimento médio: **{avg_sent_str}** — {sentiment_icon(sentiment)} {sentiment.capitalize()}")

    tickets_df = run_query(f"""
        SELECT
            ticket_id,
            subject,
            status,
            priority,
            sentiment_label,
            sla_breach,
            created_at
        FROM NEXUS_APP.CORE.TICKETS
        WHERE org_id = '{ORG_ID}'
          AND customer_id = '{selected_id}'
        ORDER BY
            CASE status WHEN 'open' THEN 0 ELSE 1 END,
            created_at DESC
        LIMIT 10
    """)

    if tickets_df.empty:
        st.info("Nenhum ticket encontrado.")
    else:
        st.dataframe(
            tickets_df.rename(columns={
                "TICKET_ID": "ID", "SUBJECT": "Assunto",
                "STATUS": "Status", "PRIORITY": "Prioridade",
                "SENTIMENT_LABEL": "Sentimento",
                "SLA_BREACH": "SLA Breach", "CREATED_AT": "Criado em",
            }),
            hide_index=True,
            use_container_width=True,
        )

st.divider()

# ─── Subscrições + Contratos ─────────────────────────────────────────────────

col_sub, col_cont = st.columns(2)

with col_sub:
    st.subheader("💳 Subscrições Ativas")

    subs_df = run_query(f"""
        SELECT
            plan_name,
            plan_tier,
            seats,
            mrr,
            arr,
            current_period_end  AS renewal_date,
            auto_renewal        AS auto_renew
        FROM NEXUS_APP.CORE.SUBSCRIPTIONS
        WHERE org_id = '{ORG_ID}'
          AND customer_id = '{selected_id}'
          AND status = 'active'
        ORDER BY arr DESC
    """)

    if subs_df.empty:
        st.info("Nenhuma subscrição ativa.")
    else:
        st.dataframe(
            subs_df.rename(columns={
                "PLAN_NAME": "Plano", "PLAN_TIER": "Tier", "SEATS": "Seats",
                "MRR": "MRR", "ARR": "ARR",
                "RENEWAL_DATE": "Renovação", "AUTO_RENEW": "Auto-Renovação",
            }),
            hide_index=True,
            use_container_width=True,
            column_config={
                "MRR": st.column_config.NumberColumn(format="$%.0f"),
                "ARR": st.column_config.NumberColumn(format="$%.0f"),
            },
        )


with col_cont:
    st.subheader("📋 Contratos")

    cont_df = run_query(f"""
        SELECT
            contract_name,
            contract_value,
            start_date,
            end_date,
            status,
            auto_renewal
        FROM NEXUS_APP.CORE.CONTRACTS
        WHERE org_id = '{ORG_ID}'
          AND customer_id = '{selected_id}'
        ORDER BY end_date ASC
    """)

    if cont_df.empty:
        st.info("Nenhum contrato encontrado.")
    else:
        st.dataframe(
            cont_df.rename(columns={
                "CONTRACT_NAME": "Contrato", "CONTRACT_VALUE": "Valor",
                "START_DATE": "Início", "END_DATE": "Fim",
                "STATUS": "Status", "AUTO_RENEWAL": "Auto-Renovação",
            }),
            hide_index=True,
            use_container_width=True,
            column_config={
                "Valor": st.column_config.NumberColumn(format="$%.0f"),
            },
        )

st.divider()

# ─── Recomendações de IA ──────────────────────────────────────────────────────

st.subheader("💡 Recomendações de IA para este cliente")

recs_df = run_query(f"""
    SELECT
        recommendation_type AS type,
        priority,
        recommendation_text AS recommendation,
        expected_impact_usd AS impact,
        confidence_score    AS confidence,
        owner_role          AS owner,
        created_at
    FROM NEXUS_APP.AI.RECOMMENDATIONS
    WHERE org_id = '{ORG_ID}'
      AND entity_id = '{selected_id}'
      AND status = 'pending'
      AND is_active = TRUE
    ORDER BY
        CASE priority WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END,
        expected_impact_usd DESC
""")

if recs_df.empty:
    st.success("✅ Nenhuma recomendação pendente para este cliente.")
else:
    for _, rec in recs_df.iterrows():
        prio_icon = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}.get(rec["PRIORITY"], "⚪")
        impact    = f"${float(rec['IMPACT']) / 1_000:.0f}K" if rec["IMPACT"] else "—"
        conf      = f"{float(rec['CONFIDENCE']) * 100:.0f}%" if rec["CONFIDENCE"] else "—"
        col_rec, col_btn = st.columns([6, 1])
        with col_rec:
            st.markdown(
                f"{prio_icon} `{rec['TYPE']}` · Impacto **{impact}** · Confiança {conf} · Owner: *{rec['OWNER']}*  \n"
                f"_{rec['RECOMMENDATION']}_"
            )
        with col_btn:
            st.button("Agir →", key=f"rec_{selected_id}_{rec['TYPE']}")
        st.divider()

# ─── Ação de churn recomendada ────────────────────────────────────────────────

if str(r["CHURN_RISK_LEVEL"]) in ("HIGH", "MEDIUM"):
    action = r["CHURN_RECOMMENDED_ACTION"]
    arr_risk = float(r["EXPECTED_REVENUE_AT_RISK"] or 0)
    level = str(r["CHURN_RISK_LEVEL"])
    icon  = risk_icon(level)

    if level == "HIGH":
        st.error(
            f"{icon} **Risco {level}** — ARR em risco: **${arr_risk / 1_000:.0f}K**  \n"
            f"**Ação recomendada:** {action}"
        )
    else:
        st.warning(
            f"{icon} **Risco {level}** — ARR em risco: **${arr_risk / 1_000:.0f}K**  \n"
            f"**Ação recomendada:** {action}"
        )
