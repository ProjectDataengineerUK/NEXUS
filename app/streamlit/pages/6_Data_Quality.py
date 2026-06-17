"""
NEXUS AI DataOps — Data Quality Monitor
Sprint 6: freshness, completude, duplicatas, SLAs e histórico de checks.
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Data Quality · NEXUS",
    page_icon="✅",
    layout="wide",
)

ORG_ID = "ORG-DEMO-001"

STATUS_ICON = {"PASS": "✅", "WARN": "⚠️", "FAIL": "❌"}
STATUS_COLOR = {"PASS": "green", "WARN": "orange", "FAIL": "red"}


@st.cache_resource
def get_session():
    return get_active_session()


def run_sql(sql: str) -> pd.DataFrame:
    return get_session().sql(sql).to_pandas()


def run_dq_checks():
    """Executa checks de qualidade e grava em AUDIT.DATA_QUALITY_RESULTS."""
    session = get_session()

    checks = [
        # Freshness — Dynamic Tables (minutos desde último refresh)
        ("NEXUS_APP.MART.CUSTOMER_360",   "freshness_minutes",
         "SELECT DATEDIFF('minute', LAST_ALTERED, CURRENT_TIMESTAMP()) "
         "FROM INFORMATION_SCHEMA.TABLES "
         "WHERE TABLE_SCHEMA='MART' AND TABLE_NAME='CUSTOMER_360'",
         120.0),

        # Completude — customers sem email
        ("NEXUS_APP.CORE.CUSTOMERS", "null_rate_email",
         "SELECT ROUND(COUNT_IF(email IS NULL OR email='')*100.0/NULLIF(COUNT(*),0),2) "
         "FROM NEXUS_APP.CORE.CUSTOMERS WHERE org_id='" + ORG_ID + "'",
         5.0),

        # Completude — customers sem NPS
        ("NEXUS_APP.CORE.CUSTOMERS", "null_rate_nps",
         "SELECT ROUND(COUNT_IF(nps_score IS NULL)*100.0/NULLIF(COUNT(*),0),2) "
         "FROM NEXUS_APP.CORE.CUSTOMERS WHERE org_id='" + ORG_ID + "'",
         30.0),

        # Unicidade — customer_id duplicado
        ("NEXUS_APP.CORE.CUSTOMERS", "duplicate_customer_ids",
         "SELECT COUNT(*)-COUNT(DISTINCT customer_id) "
         "FROM NEXUS_APP.CORE.CUSTOMERS WHERE org_id='" + ORG_ID + "'",
         0.0),

        # Volume mínimo — customers ativos
        ("NEXUS_APP.CORE.CUSTOMERS", "active_customer_count",
         "SELECT COUNT(*) FROM NEXUS_APP.CORE.CUSTOMERS "
         "WHERE org_id='" + ORG_ID + "' AND status='active'",
         1.0),

        # Validade — health_score no range 0-100
        ("NEXUS_APP.MART.CUSTOMER_360", "invalid_health_score",
         "SELECT COUNT_IF(health_score < 0 OR health_score > 100) "
         "FROM NEXUS_APP.MART.CUSTOMER_360",
         0.0),

        # Completude — recommendations sem texto
        ("NEXUS_APP.AI.RECOMMENDATIONS", "null_rec_text",
         "SELECT COUNT_IF(recommendation_text IS NULL OR recommendation_text='') "
         "FROM NEXUS_APP.AI.RECOMMENDATIONS WHERE org_id='" + ORG_ID + "'",
         0.0),

        # Completude — churn scores pontuados nas últimas 48h
        ("NEXUS_APP.AI.CHURN_SCORES", "stale_churn_scores",
         "SELECT COUNT_IF(scored_at < DATEADD('hour',-48,CURRENT_TIMESTAMP())) "
         "FROM NEXUS_APP.AI.CHURN_SCORES WHERE org_id='" + ORG_ID + "'",
         0.0),
    ]

    results = []
    for table, metric, query, threshold in checks:
        try:
            val_row = session.sql(query).collect()
            val = float(val_row[0][0] or 0)

            if metric in ("freshness_minutes", "null_rate_email", "null_rate_nps"):
                status = "PASS" if val <= threshold else ("WARN" if val <= threshold * 2 else "FAIL")
            elif metric in ("active_customer_count",):
                status = "PASS" if val >= threshold else "FAIL"
            else:
                status = "PASS" if val <= threshold else "FAIL"

            session.sql(f"""
                INSERT INTO NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
                    (org_id, table_name, metric_name, metric_value, threshold, status)
                VALUES
                    ('{ORG_ID}', '{table}', '{metric}', {val:.6f}, {threshold:.6f}, '{status}')
            """).collect()
            results.append({"table": table.split(".")[-1], "metric": metric,
                             "value": val, "threshold": threshold, "status": status})
        except Exception as e:
            results.append({"table": table.split(".")[-1], "metric": metric,
                             "value": None, "threshold": threshold,
                             "status": "FAIL", "error": str(e)})

    return pd.DataFrame(results)


# ─── Sidebar ──────────────────────────────────────────────────────────────────

with st.sidebar:
    st.title("✅ Data Quality")
    st.divider()

    dq_view = st.radio("Visualização", [
        "📊 Status Atual",
        "📜 Histórico",
        "🕐 Freshness",
    ])

    st.divider()
    if st.button("▶️ Executar Checks", type="primary"):
        with st.spinner("Executando checks de qualidade…"):
            results_df = run_dq_checks()
        st.session_state["dq_last_run"] = results_df
        st.success(f"{len(results_df)} checks executados.")
        st.rerun()

    st.page_link("Home.py", label="← Home", icon="⚡")
    st.page_link("pages/7_Admin.py", label="⚙️ Admin")


st.markdown("## ✅ Data Quality Monitor")
st.caption("Monitoramento contínuo de completude, freshness, validade e volume dos data products NEXUS.")


# ═════════════════════════════════════════════════════════════════════════════
# STATUS ATUAL
# ═════════════════════════════════════════════════════════════════════════════

if dq_view == "📊 Status Atual":

    latest_df = run_sql(f"""
        SELECT
            table_name,
            metric_name,
            metric_value,
            threshold,
            status,
            measured_at
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY table_name, metric_name
                                   ORDER BY measured_at DESC) AS rn
            FROM NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
            WHERE org_id = '{ORG_ID}'
        )
        WHERE rn = 1
        ORDER BY
            CASE status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END,
            table_name, metric_name
    """)

    if latest_df.empty:
        st.info("Nenhum resultado disponível. Clique em 'Executar Checks' na sidebar.")
    else:
        total  = len(latest_df)
        passed = int((latest_df["STATUS"] == "PASS").sum())
        warned = int((latest_df["STATUS"] == "WARN").sum())
        failed = int((latest_df["STATUS"] == "FAIL").sum())
        score  = int(passed / total * 100) if total else 0

        k1, k2, k3, k4 = st.columns(4)
        k1.metric("Score DQ", f"{score}%",
                  delta="healthy" if score >= 80 else "atenção necessária")
        k2.metric("✅ Passou",  passed)
        k3.metric("⚠️ Alerta",  warned)
        k4.metric("❌ Falhou",  failed)

        if failed > 0:
            st.error(f"{failed} check(s) falhando — ação requerida.")
        elif warned > 0:
            st.warning(f"{warned} check(s) em alerta.")
        else:
            st.success("Todos os checks passando.")

        st.divider()

        for table_name, group in latest_df.groupby("TABLE_NAME"):
            st.markdown(f"#### 📦 `{table_name}`")
            for _, row in group.iterrows():
                icon = STATUS_ICON.get(row["STATUS"], "❓")
                val  = row["METRIC_VALUE"]
                thr  = row["THRESHOLD"]
                val_s = f"{val:.2f}" if val is not None else "—"
                thr_s = f"{thr:.2f}" if thr is not None else "—"

                col1, col2, col3 = st.columns([3, 1, 1])
                col1.markdown(f"{icon} `{row['METRIC_NAME']}`")
                col2.markdown(f"**{val_s}** (threshold: {thr_s})")
                col3.caption(str(row["MEASURED_AT"])[:16])
            st.divider()


# ═════════════════════════════════════════════════════════════════════════════
# HISTÓRICO
# ═════════════════════════════════════════════════════════════════════════════

elif dq_view == "📜 Histórico":

    hist_df = run_sql(f"""
        SELECT
            DATE_TRUNC('hour', measured_at) AS hora,
            COUNT(*)                         AS total_checks,
            COUNT_IF(status='PASS')          AS passed,
            COUNT_IF(status='WARN')          AS warned,
            COUNT_IF(status='FAIL')          AS failed
        FROM NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
        WHERE org_id = '{ORG_ID}'
          AND measured_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY 1 DESC
        LIMIT 168
    """)

    if hist_df.empty:
        st.info("Sem histórico disponível nos últimos 7 dias.")
    else:
        st.markdown("### Histórico de Checks — últimos 7 dias")
        chart_df = hist_df.set_index("HORA")[["PASSED", "WARNED", "FAILED"]]
        st.line_chart(chart_df, height=250)

        st.dataframe(
            hist_df.rename(columns={
                "HORA": "Hora", "TOTAL_CHECKS": "Total",
                "PASSED": "Passou", "WARNED": "Alerta", "FAILED": "Falhou"
            }),
            hide_index=True,
            use_container_width=True,
        )

    raw_df = run_sql(f"""
        SELECT table_name, metric_name, metric_value, threshold, status, measured_at
        FROM NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
        WHERE org_id = '{ORG_ID}'
        ORDER BY measured_at DESC
        LIMIT 200
    """)

    if not raw_df.empty:
        st.divider()
        st.markdown("### Log detalhado")
        st.dataframe(raw_df, hide_index=True, use_container_width=True)

        st.download_button(
            "⬇️ Exportar CSV",
            raw_df.to_csv(index=False).encode(),
            file_name="nexus_dq_history.csv",
            mime="text/csv",
        )


# ═════════════════════════════════════════════════════════════════════════════
# FRESHNESS
# ═════════════════════════════════════════════════════════════════════════════

else:
    st.markdown("### 🕐 Freshness — Dynamic Tables & Pipelines")

    fresh_df = run_sql("""
        SELECT
            t.TABLE_SCHEMA  AS schema_name,
            t.TABLE_NAME    AS table_name,
            t.TABLE_TYPE,
            t.LAST_ALTERED,
            t.ROW_COUNT,
            DATEDIFF('minute', t.LAST_ALTERED, CURRENT_TIMESTAMP()) AS minutes_stale
        FROM INFORMATION_SCHEMA.TABLES t
        WHERE t.TABLE_CATALOG = 'NEXUS_APP'
          AND t.TABLE_SCHEMA IN ('MART', 'AI', 'CORE')
          AND t.TABLE_NAME NOT LIKE 'SYS%'
        ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
    """)

    if fresh_df.empty:
        st.info("Sem dados de freshness disponíveis.")
    else:
        def freshness_status(mins):
            if mins is None:
                return "UNKNOWN"
            if mins <= 60:
                return "PASS"
            elif mins <= 240:
                return "WARN"
            return "FAIL"

        fresh_df["STATUS"] = fresh_df["MINUTES_STALE"].apply(freshness_status)

        f1, f2, f3 = st.columns(3)
        f1.metric("Tabelas monitoradas", len(fresh_df))
        f2.metric("Atualizadas < 1h",
                  int((fresh_df["MINUTES_STALE"].fillna(9999) <= 60).sum()))
        f3.metric("Stale > 4h",
                  int((fresh_df["MINUTES_STALE"].fillna(0) > 240).sum()))

        st.divider()

        for _, row in fresh_df.iterrows():
            icon = STATUS_ICON.get(row["STATUS"], "❓")
            mins = row["MINUTES_STALE"]
            age  = f"{int(mins)}min atrás" if mins is not None and mins < 60 else \
                   f"{int(mins//60)}h {int(mins%60)}min atrás" if mins is not None else "desconhecido"
            rows = f"{int(row['ROW_COUNT']):,}" if row["ROW_COUNT"] else "—"

            col1, col2, col3, col4 = st.columns([0.3, 2, 1.5, 1])
            col1.markdown(f"### {icon}")
            col2.markdown(f"`{row['SCHEMA_NAME']}.{row['TABLE_NAME']}`  \n"
                          f"<small>{row['TABLE_TYPE']}</small>", unsafe_allow_html=True)
            col3.caption(f"Último refresh: {age}")
            col4.caption(f"{rows} linhas")
