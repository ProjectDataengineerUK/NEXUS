"""
NEXUS AI DataOps — Action Center
Fila de ações geradas pela IA: execução, descarte e geração de comunicações.
"""

import pandas as pd
import streamlit as st
from utils.auth import get_current_user, get_org_id
from utils.snowflake_client import execute_query, run_query

st.set_page_config(
    page_title="Action Center · NEXUS",
    page_icon="⚡",
    layout="wide",
)

ORG_ID = get_org_id()
USER   = get_current_user()

PRIORITY_ICON = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}
TYPE_LABEL = {
    "churn_prevention":   "🛡️ Retenção",
    "upsell_opportunity": "📈 Upsell",
    "contract_review":    "📋 Contrato",
    "engagement":         "🤝 Engajamento",
    "sla_breach":         "⚠️ SLA",
    "billing":            "💰 Billing",
}

# ─── Header ───────────────────────────────────────────────────────────────────

st.title("⚡ Action Center")
st.caption("Ações priorizadas pela IA — execute, descarte ou gere comunicações personalizadas.")

# ─── Métricas ─────────────────────────────────────────────────────────────────

try:
    m = run_query(f"""
        SELECT
            COUNT_IF(r.status = 'pending' AND r.is_active)          AS pending_total,
            COUNT_IF(r.status = 'pending' AND r.priority = 'HIGH')  AS high_priority,
            SUM(CASE WHEN r.status = 'pending' AND r.is_active
                     THEN r.expected_impact_usd ELSE 0 END)         AS total_impact
        FROM NEXUS_APP.AI.RECOMMENDATIONS r
        WHERE r.org_id = '{ORG_ID}'
    """)
    c1, c2, c3 = st.columns(3)
    c1.metric("Ações pendentes",       int(m["PENDING_TOTAL"].iloc[0]  or 0))
    c2.metric("Alta prioridade",       int(m["HIGH_PRIORITY"].iloc[0]  or 0))
    c3.metric("Impacto potencial",     f"${int(m['TOTAL_IMPACT'].iloc[0] or 0):,}")
except Exception:
    st.info("Nenhuma ação disponível ainda.")

st.divider()

# ─── Filtros ──────────────────────────────────────────────────────────────────

col_f1, col_f2, col_f3 = st.columns(3)
with col_f1:
    prioridades = st.multiselect("Prioridade", ["HIGH", "MEDIUM", "LOW"], default=["HIGH", "MEDIUM"])
with col_f2:
    tipos = st.multiselect(
        "Tipo de ação",
        list(TYPE_LABEL.keys()),
        format_func=lambda k: TYPE_LABEL.get(k, k),
    )
with col_f3:
    mostrar_descartadas = st.checkbox("Incluir descartadas", value=False)

priority_filter = "AND r.priority IN ({})".format(
    ", ".join(f"'{p}'" for p in prioridades)
) if prioridades else ""

type_filter = "AND r.recommendation_type IN ({})".format(
    ", ".join(f"'{t}'" for t in tipos)
) if tipos else ""

status_filter = "AND r.status IN ('pending', 'accepted', 'dismissed')" if mostrar_descartadas else "AND r.status = 'pending'"

# ─── Tabela de ações ──────────────────────────────────────────────────────────

try:
    df = run_query(f"""
        SELECT
            r.recommendation_id,
            c.customer_name,
            c.segment,
            c.churn_risk_level,
            r.recommendation_type,
            r.description,
            r.priority,
            r.expected_impact_usd,
            r.status,
            TO_CHAR(r.expires_at, 'YYYY-MM-DD') AS expires_at
        FROM NEXUS_APP.AI.RECOMMENDATIONS r
        JOIN NEXUS_APP.MART.CUSTOMER_360 c
             ON r.entity_id = c.customer_id AND c.org_id = r.org_id
        WHERE r.org_id = '{ORG_ID}'
          AND r.is_active = TRUE
          {priority_filter}
          {type_filter}
          {status_filter}
        ORDER BY
            CASE r.priority WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
            r.expected_impact_usd DESC NULLS LAST
        LIMIT 50
    """)
except Exception as e:
    st.warning(f"Não foi possível carregar ações: {e}")
    df = pd.DataFrame()

if df.empty:
    st.info("Nenhuma ação encontrada com os filtros selecionados.")
else:
    st.subheader(f"{len(df)} ações encontradas")

    for _, row in df.iterrows():
        rec_id    = row["RECOMMENDATION_ID"]
        customer  = row["CUSTOMER_NAME"]
        priority  = row["PRIORITY"]
        rec_type  = row["RECOMMENDATION_TYPE"]
        desc      = row["DESCRIPTION"]
        impact    = row["EXPECTED_IMPACT_USD"]
        status    = row["STATUS"]
        expires   = row.get("EXPIRES_AT", "—")

        icon = PRIORITY_ICON.get(priority, "⚪")
        type_label = TYPE_LABEL.get(rec_type, rec_type)

        with st.expander(f"{icon} **{customer}** — {type_label}  |  ${impact:,.0f} impacto  |  {priority}", expanded=(priority == "HIGH")):
            st.markdown(f"**Descrição:** {desc}")
            col_meta = st.columns(3)
            col_meta[0].caption(f"Segmento: {row['SEGMENT']}")
            col_meta[1].caption(f"Risco churn: {row['CHURN_RISK_LEVEL']}")
            col_meta[2].caption(f"Expira: {expires}")

            col_btn1, col_btn2, col_btn3 = st.columns([1, 1, 2])

            if status == "pending":
                if col_btn1.button("✅ Executar", key=f"exec_{rec_id}"):
                    try:
                        execute_query(f"""
                            UPDATE NEXUS_APP.AI.RECOMMENDATIONS
                            SET status = 'accepted', updated_at = CURRENT_TIMESTAMP()
                            WHERE recommendation_id = '{rec_id}'
                        """)
                        st.success("Ação marcada como executada.")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")

                if col_btn2.button("🚫 Descartar", key=f"dismiss_{rec_id}"):
                    try:
                        execute_query(f"""
                            UPDATE NEXUS_APP.AI.RECOMMENDATIONS
                            SET status = 'dismissed', updated_at = CURRENT_TIMESTAMP()
                            WHERE recommendation_id = '{rec_id}'
                        """)
                        st.info("Ação descartada.")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")

            if col_btn3.button("✉️ Gerar email", key=f"email_{rec_id}"):
                with st.spinner("Gerando email personalizado com IA..."):
                    try:
                        result = run_query(f"""
                            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                                'claude-3-5-sonnet',
                                ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
                                    'role', 'user',
                                    'content', 'Você é um especialista em customer success. ' ||
                                        'Escreva um email profissional em português para o cliente ' ||
                                        '{customer}' (segmento {row["SEGMENT"]}) sobre: {desc}. ' ||
                                        'O email deve ser conciso, empático e ter um CTA claro. ' ||
                                        'Máximo 150 palavras.'
                                ))
                            ) AS email_draft
                        """)
                        email_text = result["EMAIL_DRAFT"].iloc[0] if not result.empty else ""
                        st.text_area("Email gerado:", value=email_text, height=200, key=f"email_txt_{rec_id}")
                    except Exception as ex:
                        st.warning(f"Não foi possível gerar o email: {ex}")


# ─── Fila de Aprovação ────────────────────────────────────────────────────────

st.divider()
st.subheader("🔐 Fila de Aprovação — Ações de Alto Risco")
st.caption("Ações críticas geradas pela IA que requerem aprovação humana antes de serem executadas.")

RISK_ICON = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢"}

try:
    aq_df = run_query(f"""
        SELECT
            approval_id,
            action_type,
            risk_level,
            requested_by,
            status,
            DATEDIFF('hour', created_at, expires_at) AS hours_remaining,
            TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') AS requested_at,
            action_payload
        FROM NEXUS_APP.CORE.APPROVAL_QUEUE
        WHERE org_id = '{ORG_ID}'
          AND status = 'pending'
          AND expires_at > CURRENT_TIMESTAMP()
        ORDER BY CASE risk_level WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
                 created_at ASC
        LIMIT 30
    """)
except Exception:
    aq_df = pd.DataFrame()

if aq_df.empty:
    st.info("Nenhuma ação aguardando aprovação.")
else:
    st.markdown(f"**{len(aq_df)} ações aguardando aprovação**")

    for _, aq in aq_df.iterrows():
        appr_id    = aq["APPROVAL_ID"]
        risk       = aq["RISK_LEVEL"]
        action_t   = aq["ACTION_TYPE"]
        requester  = aq["REQUESTED_BY"]
        hours_left = int(aq["HOURS_REMAINING"] or 0)
        requested  = aq["REQUESTED_AT"]
        icon       = RISK_ICON.get(risk, "⚪")

        with st.expander(
            f"{icon} `{action_t}` — Risco **{risk}**  |  Solicitado por: {requester}  |  {hours_left}h restantes",
            expanded=(risk == "CRITICAL"),
        ):
            col_info, col_btns = st.columns([3, 1])
            with col_info:
                st.caption(f"ID: `{appr_id}`  |  Solicitado em: {requested}")
                try:
                    import json as _json
                    payload = aq["ACTION_PAYLOAD"]
                    if isinstance(payload, str):
                        payload = _json.loads(payload)
                    if payload:
                        st.json(payload, expanded=False)
                except Exception:
                    pass

            with col_btns:
                if st.button("✅ Aprovar", key=f"approve_{appr_id}", type="primary"):
                    try:
                        execute_query(f"CALL NEXUS_APP.CORE.APPROVE_ACTION('{appr_id}', '{USER}')")
                        st.success("Ação aprovada.")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")

                reject_reason = st.text_input("Motivo (rejeição):", key=f"reason_{appr_id}", placeholder="Opcional")
                if st.button("❌ Rejeitar", key=f"reject_{appr_id}"):
                    try:
                        reason_safe = reject_reason.replace("'", "''") if reject_reason else "Rejeitado manualmente"
                        execute_query(f"CALL NEXUS_APP.CORE.REJECT_ACTION('{appr_id}', '{USER}', '{reason_safe}')")
                        st.info("Ação rejeitada.")
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Erro: {ex}")
