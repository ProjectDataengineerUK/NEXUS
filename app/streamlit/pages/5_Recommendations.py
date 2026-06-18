"""
NEXUS AI DataOps — Action Center & Recommendations
Sprint 5: fila priorizada de ações, churn scores, status workflow.
"""

import json

import pandas as pd
import streamlit as st
from utils.auth import get_org_id
from utils.snowflake_client import get_session
from utils.snowflake_client import run_query as run_sql

st.set_page_config(
    page_title="Action Center · NEXUS",
    page_icon="💡",
    layout="wide",
)

ORG_ID = get_org_id()

PRIORITY_COLOR = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}
STATUS_LABEL   = {
    "pending":     "⏳ Pendente",
    "in_progress": "🔄 Em andamento",
    "completed":   "✅ Concluído",
    "dismissed":   "🚫 Descartado",
    "snoozed":     "😴 Adiado",
}
TYPE_LABEL = {
    "churn_prevention":   "🛡️ Retenção",
    "upsell_opportunity": "📈 Upsell",
    "contract_review":    "📋 Contrato",
    "engagement":         "🤝 Engajamento",
    "sla_breach":         "⚠️ SLA",
    "billing":            "💰 Billing",
}
OWNER_LABEL = {
    "customer_success": "CS",
    "sales":            "Vendas",
    "legal":            "Jurídico",
    "finance":          "Financeiro",
    "engineering":      "Engenharia",
    "data_engineering": "Data Eng",
}


def call_sp(sp_call: str):
    try:
        result = get_session().sql(sp_call).collect()
        return result[0][0] if result else "OK"
    except Exception as e:
        return f"ERRO: {e}"


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("💡 Action Center")
    st.divider()

    view_mode = st.radio(
        "Visualização",
        ["🎯 Fila de Ações", "📊 Churn Scores", "📈 Histórico"],
    )

    st.divider()

    if view_mode == "🎯 Fila de Ações":
        st.subheader("Filtros")
        filter_priority = st.multiselect(
            "Prioridade",
            ["HIGH", "MEDIUM", "LOW"],
            default=["HIGH", "MEDIUM"],
        )
        filter_type = st.multiselect(
            "Tipo",
            list(TYPE_LABEL.keys()),
            default=[],
            format_func=lambda x: TYPE_LABEL.get(x, x),
        )
        filter_owner = st.multiselect(
            "Responsável",
            list(OWNER_LABEL.keys()),
            default=[],
            format_func=lambda x: OWNER_LABEL.get(x, x),
        )
    else:
        filter_priority = ["HIGH", "MEDIUM", "LOW"]
        filter_type     = []
        filter_owner    = []

    st.divider()
    if st.button("🔄 Refresh"):
        st.cache_data.clear()
        st.rerun()

    st.page_link("Home.py", label="← Home", icon="⚡")
    st.page_link("pages/2_Customer_360.py", label="👤 Customer 360")


# ─── KPI Header ───────────────────────────────────────────────────────────────

kpi_df = run_sql(f"""
    SELECT
        COUNT(*)                                                              AS total_open,
        COUNT(CASE WHEN priority = 'HIGH' THEN 1 END)                        AS high_priority,
        COALESCE(SUM(expected_impact_usd), 0)                                AS total_impact,
        COUNT(CASE WHEN recommendation_type = 'churn_prevention' THEN 1 END) AS churn_actions,
        COUNT(CASE WHEN recommendation_type = 'upsell_opportunity' THEN 1 END) AS upsell_actions
    FROM AI.RECOMMENDATIONS
    WHERE org_id = '{ORG_ID}'
      AND is_active = TRUE
      AND status NOT IN ('completed', 'dismissed')
""")

completed_df = run_sql(f"""
    SELECT COUNT(*) AS completed_week
    FROM AI.RECOMMENDATIONS
    WHERE org_id = '{ORG_ID}'
      AND status = 'completed'
      AND acted_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
""")

st.markdown("## 💡 Action Center")
st.caption("Fila de ações priorizadas por impacto financeiro e risco. Atualizada a cada 30 minutos.")

k1, k2, k3, k4, k5 = st.columns(5)
if not kpi_df.empty:
    row = kpi_df.iloc[0]
    k1.metric("Ações abertas",     int(row["TOTAL_OPEN"]))
    k2.metric("Alta prioridade",   int(row["HIGH_PRIORITY"]))
    k3.metric("Impacto total",     f"US$ {row['TOTAL_IMPACT']:,.0f}")
    k4.metric("Ações de retenção", int(row["CHURN_ACTIONS"]))
    k5.metric("Concluídas / 7d",   int(completed_df.iloc[0]["COMPLETED_WEEK"])
              if not completed_df.empty else 0)

st.divider()


# ═════════════════════════════════════════════════════════════════════════════
# FILA DE AÇÕES
# ═════════════════════════════════════════════════════════════════════════════

if view_mode == "🎯 Fila de Ações":

    priority_filter = (
        f"AND r.priority IN ({', '.join(repr(p) for p in filter_priority)})"
        if filter_priority else ""
    )
    type_filter = (
        f"AND r.recommendation_type IN ({', '.join(repr(t) for t in filter_type)})"
        if filter_type else ""
    )
    owner_filter = (
        f"AND r.owner_role IN ({', '.join(repr(o) for o in filter_owner)})"
        if filter_owner else ""
    )

    recs_df = run_sql(f"""
        SELECT
            r.recommendation_id,
            r.entity_id              AS customer_id,
            c.name                   AS customer_name,
            c.segment,
            r.recommendation_type,
            r.priority,
            r.recommendation_text,
            r.expected_impact_usd,
            r.confidence_score,
            r.owner_role,
            r.status,
            r.created_at,
            c360.health_score,
            c360.churn_risk_level,
            c360.churn_probability,
            c360.arr,
            c360.nearest_renewal_date,
            c360.nps_score
        FROM AI.RECOMMENDATIONS r
        JOIN CORE.CUSTOMERS c
            ON r.entity_id = c.customer_id AND r.org_id = c.org_id
        LEFT JOIN MART.CUSTOMER_360 c360
            ON r.entity_id = c360.customer_id
        WHERE r.org_id = '{ORG_ID}'
          AND r.is_active = TRUE
          AND r.status NOT IN ('completed', 'dismissed')
          {priority_filter}
          {type_filter}
          {owner_filter}
        ORDER BY
            CASE r.priority WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
            r.expected_impact_usd DESC NULLS LAST
    """)

    if recs_df.empty:
        st.success("Nenhuma ação pendente com os filtros selecionados.")
    else:
        st.markdown(f"**{len(recs_df)} ação(ões) pendente(s)**")

        for _, rec in recs_df.iterrows():
            prio_icon = PRIORITY_COLOR.get(rec["PRIORITY"], "⚪")
            type_lbl  = TYPE_LABEL.get(rec["RECOMMENDATION_TYPE"], rec["RECOMMENDATION_TYPE"])
            owner_lbl = OWNER_LABEL.get(rec["OWNER_ROLE"], rec["OWNER_ROLE"])
            impact    = rec["EXPECTED_IMPACT_USD"]
            impact_s  = f"US$ {impact:,.0f}" if pd.notna(impact) else "—"
            conf      = rec["CONFIDENCE_SCORE"]
            conf_s    = f"{conf:.0%}" if pd.notna(conf) else "—"
            rec_id    = rec["RECOMMENDATION_ID"]
            short_txt = rec["RECOMMENDATION_TEXT"]
            preview   = short_txt[:90] + ("…" if len(short_txt) > 90 else "")

            with st.expander(
                f"{prio_icon} **{rec['CUSTOMER_NAME']}** · {type_lbl} · {impact_s}  —  {preview}",
                expanded=(rec["PRIORITY"] == "HIGH"),
            ):
                col_a, col_b = st.columns([2, 1])

                with col_a:
                    st.markdown(f"**Recomendação:**  \n{rec['RECOMMENDATION_TEXT']}")
                    st.divider()

                    if pd.notna(rec.get("HEALTH_SCORE")):
                        m1, m2, m3, m4 = st.columns(4)
                        m1.metric("Health Score",  f"{rec['HEALTH_SCORE']:.0f}/100")
                        m2.metric("Churn Risk",    rec["CHURN_RISK_LEVEL"] or "—")
                        m3.metric("ARR",           f"US$ {rec['ARR']:,.0f}" if pd.notna(rec.get("ARR")) else "—")
                        m4.metric("NPS",           f"{rec['NPS_SCORE']:.0f}" if pd.notna(rec.get("NPS_SCORE")) else "—")
                        if pd.notna(rec.get("NEAREST_RENEWAL_DATE")):
                            st.caption(f"📅 Renovação: {str(rec['NEAREST_RENEWAL_DATE'])[:10]}")

                with col_b:
                    st.markdown(f"**Segmento:** {rec['SEGMENT']}")
                    st.markdown(f"**Tipo:** {type_lbl}")
                    st.markdown(f"**Responsável:** {owner_lbl}")
                    st.markdown(f"**Criado em:** {str(rec['CREATED_AT'])[:10]}")
                    st.markdown(f"**Confiança:** {conf_s}")
                    st.divider()

                    btn1, btn2, btn3 = st.columns(3)

                    if btn1.button("✅ Concluir", key=f"done_{rec_id}"):
                        msg = call_sp(
                            f"CALL CORE.SP_UPDATE_RECOMMENDATION("
                            f"'{rec_id}', 'completed', 'Marcado via Action Center')"
                        )
                        if msg.startswith("OK"):
                            st.success("Ação marcada como concluída.")
                            st.cache_data.clear()
                            st.rerun()
                        else:
                            st.error(msg)

                    if btn2.button("🔄 Andamento", key=f"wip_{rec_id}"):
                        msg = call_sp(
                            f"CALL CORE.SP_UPDATE_RECOMMENDATION("
                            f"'{rec_id}', 'in_progress', NULL)"
                        )
                        if msg.startswith("OK"):
                            st.info("Status: Em andamento.")
                            st.cache_data.clear()
                            st.rerun()
                        else:
                            st.error(msg)

                    if btn3.button("🚫 Descartar", key=f"dismiss_{rec_id}"):
                        msg = call_sp(
                            f"CALL CORE.SP_UPDATE_RECOMMENDATION("
                            f"'{rec_id}', 'dismissed', 'Descartado via Action Center')"
                        )
                        if msg.startswith("OK"):
                            st.warning("Ação descartada.")
                            st.cache_data.clear()
                            st.rerun()
                        else:
                            st.error(msg)

        st.divider()
        export_df = recs_df[[
            "CUSTOMER_NAME", "RECOMMENDATION_TYPE", "PRIORITY",
            "RECOMMENDATION_TEXT", "EXPECTED_IMPACT_USD", "OWNER_ROLE", "STATUS"
        ]].copy()
        export_df.columns = [
            "Cliente", "Tipo", "Prioridade",
            "Recomendação", "Impacto (USD)", "Responsável", "Status"
        ]
        st.download_button(
            "⬇️ Exportar CSV",
            export_df.to_csv(index=False).encode(),
            file_name="nexus_action_center.csv",
            mime="text/csv",
        )


# ═════════════════════════════════════════════════════════════════════════════
# CHURN SCORES
# ═════════════════════════════════════════════════════════════════════════════

elif view_mode == "📊 Churn Scores":
    st.markdown("## 📊 Churn Scores — Modelo Snowpark ML")
    st.caption(
        "Pontuações geradas pelo modelo LogisticRegression treinado sobre dados históricos. "
        "Atualizado diariamente via `SP_RUN_CHURN_PIPELINE`."
    )

    scores_df = run_sql(f"""
        SELECT
            c.name            AS cliente,
            c.segment,
            cs.churn_probability,
            cs.risk_level,
            cs.top_drivers,
            cs.recommended_action,
            cs.expected_revenue_at_risk,
            cs.model_version,
            cs.scored_at,
            c360.health_score,
            c360.arr,
            c360.nearest_renewal_date
        FROM AI.CHURN_SCORES cs
        JOIN CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND cs.org_id = c.org_id
        LEFT JOIN MART.CUSTOMER_360 c360
            ON cs.customer_id = c360.customer_id
        WHERE cs.org_id = '{ORG_ID}'
        ORDER BY cs.churn_probability DESC
    """)

    if scores_df.empty:
        st.info("Nenhum score disponível. Execute `CALL SP_RUN_CHURN_PIPELINE('score')` no Snowflake.")
    else:
        high = int((scores_df["RISK_LEVEL"] == "HIGH").sum())
        med  = int((scores_df["RISK_LEVEL"] == "MEDIUM").sum())
        low  = int((scores_df["RISK_LEVEL"] == "LOW").sum())
        total_risk_arr = scores_df["EXPECTED_REVENUE_AT_RISK"].fillna(0).sum()

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("🔴 Alto Risco",  high)
        c2.metric("🟡 Médio Risco", med)
        c3.metric("🟢 Baixo Risco", low)
        c4.metric("ARR em Risco",   f"US$ {total_risk_arr:,.0f}")

        st.divider()

        chart_df = scores_df[["CLIENTE", "CHURN_PROBABILITY"]].set_index("CLIENTE")
        st.bar_chart(chart_df, height=250)

        st.divider()

        for _, row in scores_df.iterrows():
            risk_icon = PRIORITY_COLOR.get(row["RISK_LEVEL"], "⚪")
            prob_pct  = f"{row['CHURN_PROBABILITY']:.0%}"
            arr_risk  = f"US$ {row['EXPECTED_REVENUE_AT_RISK']:,.0f}" if pd.notna(row.get("EXPECTED_REVENUE_AT_RISK")) else "—"

            with st.expander(
                f"{risk_icon} **{row['CLIENTE']}** — {prob_pct} · {arr_risk} em risco"
            ):
                left, right = st.columns([2, 1])

                with left:
                    st.markdown(f"**Ação recomendada:**  \n{row['RECOMMENDED_ACTION']}")
                    try:
                        drivers = json.loads(row["TOP_DRIVERS"]) if isinstance(row["TOP_DRIVERS"], str) else row["TOP_DRIVERS"]
                        if drivers:
                            st.markdown("**Top drivers:**")
                            for d in drivers:
                                st.markdown(f"- `{d}`")
                    except Exception:
                        pass

                with right:
                    if pd.notna(row.get("HEALTH_SCORE")):
                        st.metric("Health Score", f"{row['HEALTH_SCORE']:.0f}/100")
                    st.metric("ARR", f"US$ {row['ARR']:,.0f}" if pd.notna(row.get("ARR")) else "—")
                    if pd.notna(row.get("NEAREST_RENEWAL_DATE")):
                        st.caption(f"📅 Renovação: {str(row['NEAREST_RENEWAL_DATE'])[:10]}")
                    st.caption(f"Modelo: `{row['MODEL_VERSION']}`")
                    st.caption(f"Pontuado em: {str(row['SCORED_AT'])[:16]}")

        st.divider()
        st.markdown("### Executar Modelo")
        run_col1, run_col2 = st.columns(2)

        if run_col1.button("🧠 Re-executar Scoring", type="primary"):
            with st.spinner("Executando modelo Snowpark ML…"):
                result = call_sp("CALL CORE.SP_RUN_CHURN_PIPELINE('score')")
            if result.startswith("OK"):
                st.success(result)
                st.cache_data.clear()
                st.rerun()
            else:
                st.error(result)

        if run_col2.button("💡 Gerar Recomendações via Cortex"):
            with st.spinner("Gerando recomendações com Cortex Complete…"):
                result = call_sp("CALL CORE.SP_RUN_CHURN_PIPELINE('recs')")
            if result.startswith("OK"):
                st.success(result)
                st.cache_data.clear()
                st.rerun()
            else:
                st.error(result)


# ═════════════════════════════════════════════════════════════════════════════
# HISTÓRICO
# ═════════════════════════════════════════════════════════════════════════════

else:
    st.markdown("## 📈 Histórico de Ações")

    hist_df = run_sql(f"""
        SELECT
            c.name                   AS cliente,
            r.recommendation_type,
            r.priority,
            r.expected_impact_usd,
            r.owner_role,
            r.status,
            r.created_at,
            r.acted_at
        FROM AI.RECOMMENDATIONS r
        JOIN CORE.CUSTOMERS c
            ON r.entity_id = c.customer_id AND r.org_id = c.org_id
        WHERE r.org_id = '{ORG_ID}'
        ORDER BY r.created_at DESC
        LIMIT 100
    """)

    if hist_df.empty:
        st.info("Nenhuma recomendação registrada ainda.")
    else:
        total_completed   = int((hist_df["STATUS"] == "completed").sum())
        total_impact_done = hist_df[hist_df["STATUS"] == "completed"]["EXPECTED_IMPACT_USD"].fillna(0).sum()

        h1, h2, h3 = st.columns(3)
        h1.metric("Total de ações",    len(hist_df))
        h2.metric("Concluídas",        total_completed)
        h3.metric("Impacto protegido", f"US$ {total_impact_done:,.0f}")

        st.divider()

        display_df = hist_df.copy()
        display_df.columns = [
            "Cliente", "Tipo", "Prioridade",
            "Impacto (USD)", "Responsável", "Status",
            "Criado em", "Executado em"
        ]
        display_df["Tipo"]        = display_df["Tipo"].map(lambda x: TYPE_LABEL.get(x, x))
        display_df["Responsável"] = display_df["Responsável"].map(lambda x: OWNER_LABEL.get(x, x))
        display_df["Impacto (USD)"] = display_df["Impacto (USD)"].apply(
            lambda x: f"US$ {x:,.0f}" if pd.notna(x) else "—"
        )

        st.dataframe(display_df, hide_index=True, use_container_width=True)

        st.download_button(
            "⬇️ Exportar histórico completo",
            display_df.to_csv(index=False).encode(),
            file_name="nexus_recommendations_history.csv",
            mime="text/csv",
        )
