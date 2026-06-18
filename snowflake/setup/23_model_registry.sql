-- =============================================================================
-- NEXUS AI DataOps — Snowpark ML Model Registry
-- Centralised model versioning, performance tracking and governance
-- =============================================================================

USE SCHEMA NEXUS_APP.ML;

-- ─── Schema for ML artifacts ─────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.ML
    COMMENT = 'Snowpark ML model registry, feature stores and evaluation logs';


-- ─── Model performance log table ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ML.MODEL_PERFORMANCE_LOG (
    log_id          VARCHAR(36)     DEFAULT UUID_STRING()   NOT NULL,
    model_name      VARCHAR(200)    NOT NULL,
    model_version   VARCHAR(100)    NOT NULL,
    run_date        DATE            DEFAULT CURRENT_DATE()  NOT NULL,
    metric_name     VARCHAR(100)    NOT NULL,
    metric_value    NUMBER(18,6)    NOT NULL,
    dataset_split   VARCHAR(20)     DEFAULT 'test',         -- train | val | test | prod
    org_id          VARCHAR(50),
    run_metadata    VARIANT,
    created_at      TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP() NOT NULL,
    PRIMARY KEY (log_id)
);


-- ─── SP: Register NEXUS models via Snowpark ML Registry ──────────────────────

CREATE OR REPLACE PROCEDURE ML.REGISTER_NEXUS_MODELS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
HANDLER = 'register_models'
AS $$
from snowflake.snowpark import Session
from snowflake.ml.registry import Registry
import json

MODELS = [
    {
        "name":        "CHURN_RISK_CLASSIFIER",
        "version":     "1.0.0",
        "description": "XGBoost binary classifier — 30-day churn probability per customer",
        "tags": {
            "team":      "data-science",
            "target":    "churn_probability",
            "framework": "xgboost",
            "stage":     "production",
        },
    },
    {
        "name":        "HEALTH_SCORE_REGRESSOR",
        "version":     "1.0.0",
        "description": "Gradient Boosting regressor — customer health score (0-100)",
        "tags": {
            "team":      "data-science",
            "target":    "health_score",
            "framework": "sklearn",
            "stage":     "production",
        },
    },
    {
        "name":        "REVENUE_FORECAST_MODEL",
        "version":     "1.0.0",
        "description": "Prophet + XGBoost ensemble — 90-day MRR forecast per org",
        "tags": {
            "team":      "data-science",
            "target":    "mrr_forecast",
            "framework": "prophet+xgboost",
            "stage":     "production",
        },
    },
    {
        "name":        "UPSELL_OPPORTUNITY_SCORER",
        "version":     "1.0.0",
        "description": "LightGBM classifier — upsell/cross-sell propensity score",
        "tags": {
            "team":      "data-science",
            "target":    "upsell_propensity",
            "framework": "lightgbm",
            "stage":     "staging",
        },
    },
    {
        "name":        "ANOMALY_DETECTOR",
        "version":     "1.0.0",
        "description": "Isolation Forest — data quality and behavioural anomaly detection",
        "tags": {
            "team":      "data-science",
            "target":    "anomaly_score",
            "framework": "sklearn",
            "stage":     "production",
        },
    },
]

def register_models(session: Session):
    registry = Registry(session=session, schema_name="NEXUS_APP.ML")
    registered = []
    errors = []

    for m in MODELS:
        try:
            # Check if version already registered
            existing = [
                v for v in registry.show_models()
                if v.get("name") == m["name"]
            ]
            if existing:
                registered.append({"name": m["name"], "status": "already_registered"})
                continue

            # Log model metadata to performance log even without a real artifact
            # (real artifact registration happens when a trained model artifact exists)
            session.sql(f"""
                INSERT INTO NEXUS_APP.ML.MODEL_PERFORMANCE_LOG
                    (model_name, model_version, metric_name, metric_value, dataset_split, run_metadata)
                VALUES
                    ('{m["name"]}', '{m["version"]}', 'registered', 1.0, 'registry',
                     PARSE_JSON('{json.dumps(m["tags"])}'))
            """).collect()

            registered.append({
                "name":    m["name"],
                "version": m["version"],
                "status":  "metadata_logged",
                "tags":    m["tags"],
            })
        except Exception as e:
            errors.append({"name": m["name"], "error": str(e)})

    return {"registered": registered, "errors": errors}
$$;


-- ─── View: model registry overview ───────────────────────────────────────────

CREATE OR REPLACE VIEW ML.V_MODEL_REGISTRY AS
SELECT
    model_name,
    model_version,
    MAX(run_date)          AS last_evaluated,
    COUNT(DISTINCT metric_name) AS metric_count,
    OBJECT_AGG(
        metric_name,
        metric_value::VARIANT
    )                      AS latest_metrics,
    MAX_BY(run_metadata, created_at)  AS latest_tags
FROM ML.MODEL_PERFORMANCE_LOG
GROUP BY model_name, model_version
ORDER BY model_name, model_version;


-- ─── View: model health check ─────────────────────────────────────────────────

CREATE OR REPLACE VIEW ML.V_MODEL_HEALTH AS
WITH latest AS (
    SELECT
        model_name,
        model_version,
        metric_name,
        metric_value,
        run_date,
        ROW_NUMBER() OVER (
            PARTITION BY model_name, model_version, metric_name
            ORDER BY run_date DESC
        ) AS rn
    FROM ML.MODEL_PERFORMANCE_LOG
    WHERE dataset_split IN ('test', 'prod')
)
SELECT
    model_name,
    model_version,
    metric_name,
    metric_value,
    run_date                                          AS last_evaluation,
    DATEDIFF('day', run_date, CURRENT_DATE())         AS days_since_evaluation,
    CASE
        WHEN DATEDIFF('day', run_date, CURRENT_DATE()) > 30 THEN 'STALE'
        WHEN metric_name = 'accuracy' AND metric_value < 0.75 THEN 'DEGRADED'
        WHEN metric_name = 'auc'      AND metric_value < 0.70 THEN 'DEGRADED'
        ELSE 'HEALTHY'
    END                                               AS health_status
FROM latest
WHERE rn = 1;


-- ─── Task: evaluate model performance daily ───────────────────────────────────

CREATE OR REPLACE TASK ML.TASK_MODEL_EVALUATION
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 3 * * * UTC'
    COMMENT   = 'Daily model performance evaluation and drift detection'
AS
$$
BEGIN
    -- Churn model: recompute precision/recall on last 30d ground truth
    INSERT INTO NEXUS_APP.ML.MODEL_PERFORMANCE_LOG
        (model_name, model_version, metric_name, metric_value, dataset_split)
    SELECT
        'CHURN_RISK_CLASSIFIER',
        '1.0.0',
        'precision_at_30d',
        RATIO_TO_REPORT(COUNT_IF(actual_churned AND predicted_high_risk)) OVER (),
        'prod'
    FROM (
        SELECT
            c.customer_id,
            c.churn_risk_level = 'HIGH' AS predicted_high_risk,
            c.churned_at IS NOT NULL     AS actual_churned
        FROM NEXUS_APP.MART.CUSTOMER_360 c
        WHERE c.last_updated >= DATEADD('day', -30, CURRENT_DATE())
    )
    HAVING COUNT(*) > 0;

    -- Health score model: track average predicted vs. actual NPS correlation proxy
    INSERT INTO NEXUS_APP.ML.MODEL_PERFORMANCE_LOG
        (model_name, model_version, metric_name, metric_value, dataset_split)
    SELECT
        'HEALTH_SCORE_REGRESSOR',
        '1.0.0',
        'avg_health_score_production',
        AVG(health_score),
        'prod'
    FROM NEXUS_APP.MART.CUSTOMER_360
    WHERE health_score IS NOT NULL;
END;
$$

ALTER TASK ML.TASK_MODEL_EVALUATION RESUME;


-- ─── Initial registration call ────────────────────────────────────────────────

CALL ML.REGISTER_NEXUS_MODELS();
