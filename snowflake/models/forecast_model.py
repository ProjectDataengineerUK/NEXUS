"""
NEXUS AI DataOps — Revenue Forecast Model
Usa Cortex ML FORECAST para prever receita diária nos próximos 30 dias.
Fallback: média móvel de 7 dias quando não há dados suficientes.
Escreve resultados em AI.REVENUE_FORECAST.
"""

from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lit, current_timestamp, dateadd, current_date
from snowflake.ml.modeling.forecast import Forecaster
import json

ORG_ID        = "ORG-DEMO-001"
FORECAST_DAYS = 30
MODEL_VERSION = "1.0.0-cortex-forecast"
MIN_HISTORY   = 14  # dias mínimos de histórico para treinar


def _moving_average_fallback(session: Session, org_id: str) -> list[dict]:
    """Fallback: média móvel simples dos últimos 7 dias projetada 30 dias à frente."""
    rows = session.sql("""
        SELECT AVG(total_revenue_booked) AS avg_rev
        FROM MART.REVENUE_DAILY
        WHERE org_id = ?
          AND revenue_date >= DATEADD('day', -7, CURRENT_DATE())
    """, params=[org_id]).collect()

    avg = float(rows[0]["AVG_REV"] or 0) if rows else 0.0
    forecasts = []
    for i in range(1, FORECAST_DAYS + 1):
        forecasts.append({
            "org_id":         org_id,
            "forecast_date":  f"DATEADD('day', {i}, CURRENT_DATE())",
            "forecast_value": round(avg, 2),
            "lower_bound":    round(avg * 0.80, 2),
            "upper_bound":    round(avg * 1.20, 2),
            "metric":         "total_revenue",
            "model_version":  f"{MODEL_VERSION}-fallback",
        })
    return forecasts


def run(session: Session, org_id: str = ORG_ID) -> str:
    """Treina modelo de forecast e escreve predições em AI.REVENUE_FORECAST."""

    # ── Verifica histórico disponível ─────────────────────────────────────────
    count = session.sql("""
        SELECT COUNT(*) AS n
        FROM MART.REVENUE_DAILY
        WHERE org_id = ?
    """, params=[org_id]).collect()[0]["N"]

    use_fallback = count < MIN_HISTORY

    if use_fallback:
        forecasts = _moving_average_fallback(session, org_id)
        # Fallback: insere via loop
        inserted = 0
        for f in forecasts:
            session.sql("""
                INSERT INTO AI.REVENUE_FORECAST
                    (org_id, forecast_date, forecast_value, lower_bound,
                     upper_bound, metric, model_version)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, params=[
                f["org_id"], f"DATEADD('day', {inserted+1}, CURRENT_DATE())",
                f["forecast_value"], f["lower_bound"], f["upper_bound"],
                f["metric"], f["model_version"]
            ])
            inserted += 1
        return f"OK (fallback): {inserted} dias de forecast gerados via média móvel para {org_id}"

    # ── Treina com Cortex ML Forecaster ──────────────────────────────────────
    training_df = session.sql("""
        SELECT
            revenue_date  AS ds,
            org_id        AS series,
            COALESCE(total_revenue_booked, 0) AS y
        FROM MART.REVENUE_DAILY
        WHERE org_id = ?
        ORDER BY revenue_date
    """, params=[org_id])

    forecaster = Forecaster(
        timestamp_colname="DS",
        target_colname="Y",
        series_colname="SERIES",
        output_colname="FORECAST",
        prediction_interval=0.9,
    )

    forecaster.fit(training_df)

    future_df = session.sql("""
        SELECT
            DATEADD('day', SEQ4() + 1, CURRENT_DATE()) AS DS,
            ? AS SERIES
        FROM TABLE(GENERATOR(ROWCOUNT => ?))
    """, params=[org_id, FORECAST_DAYS])

    predictions = forecaster.predict(future_df)

    # ── Persiste resultados ───────────────────────────────────────────────────
    rows = predictions.collect()
    inserted = 0

    # Remove previsões antigas deste org antes de reinserir
    session.sql(
        "DELETE FROM AI.REVENUE_FORECAST WHERE org_id = ? AND forecast_date >= CURRENT_DATE()",
        params=[org_id]
    ).collect()

    for r in rows:
        session.sql("""
            INSERT INTO AI.REVENUE_FORECAST
                (org_id, forecast_date, forecast_value, lower_bound,
                 upper_bound, metric, model_version)
            VALUES (?, ?, ?, ?, ?, 'total_revenue', ?)
        """, params=[
            org_id,
            str(r["DS"]),
            float(r.get("FORECAST", 0) or 0),
            float(r.get("LOWER_BOUND", 0) or 0),
            float(r.get("UPPER_BOUND", 0) or 0),
            MODEL_VERSION,
        ]).collect()
        inserted += 1

    return f"OK: {inserted} dias de forecast gravados em AI.REVENUE_FORECAST para {org_id}"


if __name__ == "__main__":
    from snowflake.snowpark import Session
    session = Session.builder.config("connection_name", "nexus_dev").create()
    print(run(session))
    session.close()
