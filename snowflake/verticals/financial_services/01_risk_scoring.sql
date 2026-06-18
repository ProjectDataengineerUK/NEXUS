-- =============================================================================
-- NEXUS Vertical Pack — Financial Services
-- Risk scoring, compliance Q&A, portfolio anomaly detection
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

-- ─── Schema dedicado ao vertical de serviços financeiros ─────────────────────

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.VERTICAL_FINANCE
    COMMENT = 'NEXUS Vertical Pack — Financial Services: risk scoring, compliance, portfolio analytics';


-- ─── Tabela: perfil de risco financeiro por cliente ──────────────────────────

CREATE TABLE IF NOT EXISTS VERTICAL_FINANCE.CUSTOMER_RISK_PROFILE (
    profile_id          VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    customer_id         VARCHAR(50)     NOT NULL,
    risk_category       VARCHAR(50),    -- LOW | MEDIUM | HIGH | CRITICAL
    credit_score        NUMBER(5,2),
    exposure_usd        NUMBER(18,2),
    concentration_pct   NUMBER(5,2),    -- % of total portfolio
    days_past_due       INTEGER         DEFAULT 0,
    regulatory_flags    VARIANT,        -- ARRAY of compliance flags
    kyc_status          VARCHAR(30)     DEFAULT 'pending',
    aml_alert           BOOLEAN         DEFAULT FALSE,
    scored_at           TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    model_version       VARCHAR(20)     DEFAULT '1.0.0',
    PRIMARY KEY (profile_id),
    UNIQUE (org_id, customer_id)
);


-- ─── SP: Score de risco com Cortex AI + regras de negócio ────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_FINANCE.SP_COMPUTE_RISK_SCORES(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_count INTEGER;
BEGIN
    -- Merge risk scores baseado em indicadores financeiros + Cortex AI
    MERGE INTO VERTICAL_FINANCE.CUSTOMER_RISK_PROFILE tgt
    USING (
        SELECT
            c.customer_id,
            :org_id                                             AS org_id,
            c.arr_usd                                          AS exposure_usd,

            -- Concentração no portfólio
            ROUND(
                c.arr_usd * 100.0 / NULLIF(SUM(c.arr_usd) OVER (), 0),
                2
            )                                                  AS concentration_pct,

            -- Score de crédito proxy (baseado em health score + pagamentos)
            ROUND(
                GREATEST(300, LEAST(850,
                    300 + (c.health_score * 5.5)
                )),
                0
            )                                                  AS credit_score,

            -- Categoria de risco
            CASE
                WHEN c.churn_risk_level = 'HIGH'   AND c.health_score < 30 THEN 'CRITICAL'
                WHEN c.churn_risk_level = 'HIGH'                            THEN 'HIGH'
                WHEN c.churn_risk_level = 'MEDIUM' AND c.health_score < 50 THEN 'HIGH'
                WHEN c.churn_risk_level = 'MEDIUM'                         THEN 'MEDIUM'
                ELSE 'LOW'
            END                                                AS risk_category,

            -- Dias em atraso (proxy via tickets de billing)
            COALESCE((
                SELECT MAX(DATEDIFF('day', t.created_at, CURRENT_TIMESTAMP()))
                FROM NEXUS_APP.CORE.TICKETS t
                WHERE t.customer_id = c.customer_id
                  AND t.org_id      = c.org_id
                  AND t.category    = 'billing'
                  AND t.status      = 'open'
            ), 0)                                              AS days_past_due,

            -- AML: flag se volume inesperadamente alto
            (c.arr_usd > 500000 AND c.health_score < 20)      AS aml_alert

        FROM NEXUS_APP.MART.CUSTOMER_360 c
        WHERE c.org_id = :org_id
    ) src
    ON tgt.customer_id = src.customer_id AND tgt.org_id = src.org_id
    WHEN MATCHED THEN UPDATE SET
        risk_category     = src.risk_category,
        credit_score      = src.credit_score,
        exposure_usd      = src.exposure_usd,
        concentration_pct = src.concentration_pct,
        days_past_due     = src.days_past_due,
        aml_alert         = src.aml_alert,
        scored_at         = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (org_id, customer_id, risk_category, credit_score, exposure_usd,
         concentration_pct, days_past_due, aml_alert)
    VALUES
        (src.org_id, src.customer_id, src.risk_category, src.credit_score,
         src.exposure_usd, src.concentration_pct, src.days_past_due, src.aml_alert);

    SELECT COUNT(*) INTO v_count FROM VERTICAL_FINANCE.CUSTOMER_RISK_PROFILE
    WHERE org_id = :org_id;

    RETURN 'Scored ' || v_count::VARCHAR || ' customers.';
END;
$$;


-- ─── SP: Q&A de compliance regulatório via Cortex AI ─────────────────────────

CREATE OR REPLACE PROCEDURE VERTICAL_FINANCE.SP_COMPLIANCE_QA(
    question    VARCHAR,
    regulation  VARCHAR  DEFAULT 'LGPD'   -- LGPD | GDPR | SOX | PCI_DSS | BACEN
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_answer VARCHAR;
BEGIN
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'system',
            'content', 'Você é um especialista em compliance regulatório para serviços financeiros no Brasil. Responda perguntas sobre ' || :regulation || ' de forma objetiva e cite artigos/seções quando relevante. Máximo 300 palavras.'
        ), OBJECT_CONSTRUCT(
            'role', 'user',
            'content', :question
        ))
    ) INTO v_answer;
    RETURN v_answer;
END;
$$;


-- ─── View: portfolio de risco por segmento ────────────────────────────────────

CREATE OR REPLACE VIEW VERTICAL_FINANCE.V_PORTFOLIO_RISK AS
SELECT
    rp.org_id,
    c.segment,
    rp.risk_category,
    COUNT(*)                                     AS customer_count,
    SUM(rp.exposure_usd)                         AS total_exposure_usd,
    ROUND(AVG(rp.credit_score), 0)               AS avg_credit_score,
    ROUND(AVG(rp.concentration_pct), 2)          AS avg_concentration_pct,
    COUNT_IF(rp.aml_alert)                       AS aml_alerts,
    COUNT_IF(rp.days_past_due > 30)              AS overdue_30d,
    MAX(rp.scored_at)                            AS last_scored
FROM VERTICAL_FINANCE.CUSTOMER_RISK_PROFILE rp
JOIN NEXUS_APP.MART.CUSTOMER_360 c
     ON rp.customer_id = c.customer_id AND rp.org_id = c.org_id
GROUP BY 1, 2, 3;


-- ─── Task: recomputar scores diariamente ──────────────────────────────────────

CREATE OR REPLACE TASK VERTICAL_FINANCE.TASK_RISK_SCORING
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'
    COMMENT   = 'Daily financial risk scoring for all active orgs'
AS
DECLARE v_org VARCHAR;
BEGIN
    FOR rec IN (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.ORGANIZATIONS WHERE is_active = TRUE) DO
        v_org := rec.org_id;
        CALL VERTICAL_FINANCE.SP_COMPUTE_RISK_SCORES(:v_org);
    END FOR;
END;

ALTER TASK VERTICAL_FINANCE.TASK_RISK_SCORING RESUME;
