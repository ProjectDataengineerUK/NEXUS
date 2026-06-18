"""
NEXUS AI DataOps — Anomaly Detection Model
Usa Cortex ML DetectAnomalies sobre métricas operacionais diárias.
Detecta desvios em receita, volume de tickets, health score e ARR em risco.
Escreve alertas em AI.ANOMALY_ALERTS.
"""

from snowflake.snowpark import Session
from snowflake.ml.modeling.anomaly_detection import AnomalyDetector

ORG_ID        = "ORG-DEMO-001"
MODEL_VERSION = "1.0.0-anomaly"
MIN_HISTORY   = 7   # dias mínimos para detectar anomalias

METRICS = [
    {
        "name":    "daily_revenue",
        "table":   "MART.REVENUE_DAILY",
        "ts_col":  "REVENUE_DATE",
        "val_col": "TOTAL_REVENUE_BOOKED",
    },
    {
        "name":    "daily_new_mrr",
        "table":   "MART.REVENUE_DAILY",
        "ts_col":  "REVENUE_DATE",
        "val_col": "NET_NEW_MRR",
    },
    {
        "name":    "avg_health_score",
        "table":   "MART.EXECUTIVE_KPIS",
        "ts_col":  "SNAPSHOT_DATE",
        "val_col": "AVG_HEALTH_SCORE",
    },
    {
        "name":    "arr_at_risk",
        "table":   "MART.EXECUTIVE_KPIS",
        "ts_col":  "SNAPSHOT_DATE",
        "val_col": "ARR_AT_RISK",
    },
]


def _severity(deviation_pct: float) -> str:
    abs_dev = abs(deviation_pct)
    if abs_dev >= 50:
        return "HIGH"
    elif abs_dev >= 25:
        return "MEDIUM"
    return "LOW"


def _detect_metric(session: Session, org_id: str, metric: dict) -> int:
    """Detecta anomalias em uma métrica e retorna count de anomalias inseridas."""

    df = session.sql(f"""
        SELECT
            {metric['ts_col']}  AS DS,
            ?                   AS SERIES,
            {metric['val_col']} AS Y
        FROM {metric['table']}
        WHERE org_id = ?
          AND {metric['ts_col']} >= DATEADD('day', -{MIN_HISTORY * 4}, CURRENT_DATE())
          AND {metric['val_col']} IS NOT NULL
        ORDER BY DS
    """, params=[org_id, org_id])

    count = df.count()
    if count < MIN_HISTORY:
        return 0

    detector = AnomalyDetector(
        timestamp_colname="DS",
        target_colname="Y",
        series_colname="SERIES",
        output_colname="IS_ANOMALY",
    )

    try:
        detector.fit(df)
        result_df = detector.predict(df)
    except Exception:
        return 0

    rows = result_df.collect()
    inserted = 0

    for r in rows:
        if not r.get("IS_ANOMALY"):
            continue

        actual   = float(r.get("Y", 0) or 0)
        expected = float(r.get("FORECAST", actual) or actual)
        dev_pct  = ((actual - expected) / expected * 100) if expected else 0.0

        session.sql("""
            INSERT INTO AI.ANOMALY_ALERTS
                (org_id, metric_name, metric_date, metric_value, expected_value,
                 deviation_pct, is_anomaly, severity, model_version)
            VALUES (?, ?, ?, ?, ?, ?, TRUE, ?, ?)
        """, params=[
            org_id,
            metric["name"],
            str(r["DS"]),
            round(actual, 4),
            round(expected, 4),
            round(dev_pct, 4),
            _severity(dev_pct),
            MODEL_VERSION,
        ]).collect()
        inserted += 1

    return inserted


def run(session: Session, org_id: str = ORG_ID) -> str:
    """Detecta anomalias em todas as métricas operacionais e escreve alertas."""

    # Limpa alertas antigos deste org (manter apenas últimos 7 dias)
    session.sql("""
        DELETE FROM AI.ANOMALY_ALERTS
        WHERE org_id = ?
          AND metric_date < DATEADD('day', -7, CURRENT_DATE())
    """, params=[org_id]).collect()

    total = 0
    for metric in METRICS:
        total += _detect_metric(session, org_id, metric)

    return f"OK: {total} anomalias detectadas e gravadas em AI.ANOMALY_ALERTS para {org_id}"


if __name__ == "__main__":
    from snowflake.snowpark import Session
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
