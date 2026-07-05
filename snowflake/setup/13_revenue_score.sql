-- NEXUS AI DataOps — Revenue Opportunity Score
-- Sprint 2 — P1: DT + stored procedure para scoring de oportunidade

USE DATABASE NEXUS_APP;

CREATE TABLE IF NOT EXISTS MART.REVENUE_OPPORTUNITY_SCORE (
    score_id              VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    customer_id           VARCHAR(36)   NOT NULL,
    org_id                VARCHAR(50)   NOT NULL,
    opportunity_score     DECIMAL(4,2)  CHECK (opportunity_score BETWEEN 0 AND 1),
    opportunity_type      VARCHAR(50)   CHECK (opportunity_type IN ('upsell','expansion','retention','renewal','cross_sell')),
    estimated_revenue_usd DECIMAL(18,2),
    confidence            DECIMAL(4,2)  CHECK (confidence BETWEEN 0 AND 1),
    reasoning             TEXT,
    scored_at             TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_revenue_opportunity PRIMARY KEY (score_id)
);

ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE
    ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);

GRANT SELECT ON TABLE MART.REVENUE_OPPORTUNITY_SCORE TO APPLICATION ROLE NEXUS_VIEWER;

-- SP de scoring (executa via TASK_REFRESH_REVENUE_SCORE)
CREATE OR REPLACE PROCEDURE MART.SP_SCORE_REVENUE_OPPORTUNITIES()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    rows_inserted INTEGER DEFAULT 0;
BEGIN
    -- Remove scores antigos (>6h) para recalcular
    DELETE FROM MART.REVENUE_OPPORTUNITY_SCORE
    WHERE scored_at < DATEADD('hour', -6, CURRENT_TIMESTAMP());

    -- Insere scores para clientes sem score recente
    INSERT INTO MART.REVENUE_OPPORTUNITY_SCORE (
        customer_id, org_id, opportunity_score, opportunity_type,
        estimated_revenue_usd, confidence, reasoning
    )
    SELECT
        c.customer_id,
        c.org_id,
        CASE
            WHEN cs.churn_probability < 0.2 AND c.arr > 50000 THEN 0.90
            WHEN cs.churn_probability < 0.2 AND c.arr > 20000 THEN 0.75
            WHEN cs.churn_probability < 0.3 AND c.arr > 10000 THEN 0.65
            WHEN cs.churn_probability < 0.5                   THEN 0.50
            WHEN cs.churn_probability < 0.7                   THEN 0.30
            ELSE 0.10
        END                                                      AS opportunity_score,
        CASE
            WHEN cs.churn_probability < 0.3 AND c.arr > 30000 THEN 'upsell'
            WHEN cs.churn_probability < 0.3                    THEN 'expansion'
            WHEN cs.churn_probability < 0.5                    THEN 'cross_sell'
            WHEN c.contract_end_date <= DATEADD('day', 90, CURRENT_DATE()) THEN 'renewal'
            ELSE 'retention'
        END                                                      AS opportunity_type,
        c.arr * CASE
            WHEN cs.churn_probability < 0.2 THEN 0.25
            WHEN cs.churn_probability < 0.4 THEN 0.12
            WHEN cs.churn_probability < 0.6 THEN 0.05
            ELSE 0.02
        END                                                      AS estimated_revenue_usd,
        GREATEST(0.1, 1 - cs.churn_probability)                 AS confidence,
        'Score baseado em churn_probability=' || cs.churn_probability::VARCHAR
            || ' ARR=' || c.arr::VARCHAR
            || ' lifecycle=' || c.lifecycle_stage                AS reasoning
    FROM CORE.CUSTOMERS c
    LEFT JOIN AI.CHURN_SCORES cs ON c.customer_id = cs.customer_id
    WHERE c.lifecycle_stage != 'churned'
      AND NOT EXISTS (
          SELECT 1 FROM MART.REVENUE_OPPORTUNITY_SCORE r
          WHERE r.customer_id = c.customer_id
      );

    rows_inserted := SQLROWCOUNT;
    RETURN 'OK: ' || rows_inserted || ' scores calculados';
END;
$$;

GRANT USAGE ON PROCEDURE MART.SP_SCORE_REVENUE_OPPORTUNITIES()
    TO APPLICATION ROLE NEXUS_ADMIN;

-- DT de Revenue Score (view materializada — alternativa à Task)
CREATE OR REPLACE DYNAMIC TABLE MART.DT_REVENUE_OPPORTUNITY_SCORE
    TARGET_LAG = '6 hours'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Revenue Opportunity Score por cliente — scoring automatico a cada 6h'
AS
SELECT
    c.customer_id,
    c.org_id,
    c.name                                                           AS customer_name,
    c.arr,
    c.segment,
    COALESCE(cs.churn_probability, 0.5)                             AS churn_risk,
    CASE
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.3 AND c.arr > 30000 THEN 0.90
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.3               THEN 0.70
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.5               THEN 0.50
        ELSE 0.20
    END                                                              AS opportunity_score,
    CASE
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.3 AND c.arr > 30000 THEN 'upsell'
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.3               THEN 'expansion'
        WHEN c.contract_end_date <= DATEADD('day', 90, CURRENT_DATE()) THEN 'renewal'
        ELSE 'retention'
    END                                                              AS opportunity_type,
    c.arr * CASE
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.3 THEN 0.25
        WHEN COALESCE(cs.churn_probability, 0.5) < 0.5 THEN 0.10
        ELSE 0.03
    END                                                              AS estimated_revenue_usd,
    c.contract_end_date,
    CURRENT_TIMESTAMP()                                              AS scored_at
FROM CORE.CUSTOMERS c
LEFT JOIN AI.CHURN_SCORES cs ON c.customer_id = cs.customer_id
WHERE c.lifecycle_stage != 'churned';

GRANT SELECT ON DYNAMIC TABLE MART.DT_REVENUE_OPPORTUNITY_SCORE TO APPLICATION ROLE NEXUS_VIEWER;
