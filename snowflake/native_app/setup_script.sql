-- NEXUS AI DataOps — Native App Setup Script
-- Executado automaticamente pelo Snowflake Native App Framework
-- quando um consumer instala o app no próprio account.
-- NÃO execute manualmente — use INSTALL APPLICATION.

-- ─────────────────────────────────────────────────────────────────────────────
-- Schemas da aplicação
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS CORE;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS MART;
CREATE SCHEMA IF NOT EXISTS AUDIT;
CREATE SCHEMA IF NOT EXISTS GOVERNANCE;
CREATE SCHEMA IF NOT EXISTS CONFIG;

-- ─────────────────────────────────────────────────────────────────────────────
-- Warehouse de compute — as Dynamic Tables e Tasks abaixo requerem
-- NEXUS_COMPUTE_WH. Cria automaticamente se o consumer ainda não tiver um
-- (requer o privilégio CREATE WAREHOUSE, solicitado no manifest.yml);
-- tolerante a falha caso o account não permita ou já exista um gerenciado
-- externamente com config diferente.
-- ─────────────────────────────────────────────────────────────────────────────

EXECUTE IMMEDIATE $$
BEGIN
    CREATE WAREHOUSE IF NOT EXISTS NEXUS_COMPUTE_WH
        WAREHOUSE_SIZE      = 'XSMALL'
        AUTO_SUSPEND        = 120
        AUTO_RESUME         = TRUE
        INITIALLY_SUSPENDED = TRUE
        COMMENT             = 'Warehouse de compute do NEXUS AI DataOps — Dynamic Tables, Tasks e Cortex Agents';
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Roles de aplicação (Application Roles — Native App Framework)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE APPLICATION ROLE IF NOT EXISTS NEXUS_ADMIN;
CREATE APPLICATION ROLE IF NOT EXISTS NEXUS_ANALYST;
CREATE APPLICATION ROLE IF NOT EXISTS NEXUS_VIEWER;

-- Hierarquia
GRANT APPLICATION ROLE NEXUS_ANALYST TO APPLICATION ROLE NEXUS_ADMIN;
GRANT APPLICATION ROLE NEXUS_VIEWER  TO APPLICATION ROLE NEXUS_ANALYST;

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas CORE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CORE.CUSTOMERS (
    customer_id       VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id            VARCHAR(36)   NOT NULL,
    name              VARCHAR(500)  NOT NULL,
    email             VARCHAR(500),
    phone             VARCHAR(50),
    segment           VARCHAR(50),
    region            VARCHAR(100),
    industry          VARCHAR(100),
    status            VARCHAR(50)   DEFAULT 'active',
    lifecycle_stage   VARCHAR(50)   DEFAULT 'active',
    nps_score         INTEGER,
    arr               DECIMAL(18,2),
    mrr               DECIMAL(18,2),
    contract_end_date DATE,
    customer_since    TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at        TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (customer_id)
);

-- Migrations: garante colunas adicionadas após versões anteriores
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.CUSTOMERS ADD COLUMN IF NOT EXISTS arr               DECIMAL(18,2);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.CUSTOMERS ADD COLUMN IF NOT EXISTS mrr               DECIMAL(18,2);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.CUSTOMERS ADD COLUMN IF NOT EXISTS contract_end_date DATE;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

CREATE TABLE IF NOT EXISTS CORE.SUBSCRIPTIONS (
    subscription_id VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)   NOT NULL,
    customer_id     VARCHAR(36)   NOT NULL,
    plan_name       VARCHAR(255)  NOT NULL,
    plan_tier       VARCHAR(50)   DEFAULT 'standard',
    status          VARCHAR(50)   DEFAULT 'active',
    mrr             DECIMAL(18,2),
    arr             DECIMAL(18,2),
    renewal_date    DATE,
    started_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (subscription_id)
);

CREATE TABLE IF NOT EXISTS CORE.TICKETS (
    ticket_id       VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)   NOT NULL,
    customer_id     VARCHAR(36)   NOT NULL,
    subject         VARCHAR(1000),
    status          VARCHAR(50)   DEFAULT 'open',
    priority        VARCHAR(20)   DEFAULT 'medium',
    ticket_type     VARCHAR(50),
    sla_breach      BOOLEAN       DEFAULT FALSE,
    sentiment_score DECIMAL(4,3),
    created_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    resolved_at     TIMESTAMP_TZ,
    PRIMARY KEY (ticket_id)
);

-- Migrations: garante colunas adicionadas após versões anteriores
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.TICKETS ADD COLUMN IF NOT EXISTS ticket_type      VARCHAR(50);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.TICKETS ADD COLUMN IF NOT EXISTS sentiment_score  DECIMAL(4,3);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.TICKETS ADD COLUMN IF NOT EXISTS sentiment_label  VARCHAR(20);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

CREATE TABLE IF NOT EXISTS CORE.PRODUCT_EVENTS (
    event_id        VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)   NOT NULL,
    customer_id     VARCHAR(36)   NOT NULL,
    event_type      VARCHAR(100)  NOT NULL,
    feature_name    VARCHAR(255),
    occurred_at     TIMESTAMP_TZ  NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_id)
);

CREATE TABLE IF NOT EXISTS CORE.DOCUMENTS (
    document_id        VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id             VARCHAR(36)   NOT NULL,
    entity_id          VARCHAR(36),
    entity_type        VARCHAR(50),
    document_name      VARCHAR(500)  NOT NULL,
    document_type      VARCHAR(100)  NOT NULL DEFAULT 'other',
    stage_path         VARCHAR(1000),
    processing_status  VARCHAR(50)   DEFAULT 'pending',
    summary            TEXT,
    extracted_text     TEXT,
    document_category  VARCHAR(100),
    document_summary   TEXT,
    extracted_fields   VARIANT,
    -- Contract Intelligence fields
    contract_type      VARCHAR(100),
    contract_value_usd DECIMAL(18,2),
    start_date         DATE,
    end_date           DATE,
    auto_renewal       BOOLEAN       DEFAULT FALSE,
    governing_law      VARCHAR(255),
    ai_summary         TEXT,
    created_at         TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    processed_at       TIMESTAMP_TZ,
    PRIMARY KEY (document_id)
);

-- Migrations: contract intelligence columns added post v1.0
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS contract_type      VARCHAR(100);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS contract_value_usd DECIMAL(18,2);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS start_date         DATE;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS end_date           DATE;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS auto_renewal       BOOLEAN DEFAULT FALSE;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS governing_law      VARCHAR(255);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS ai_summary         TEXT;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

CREATE TABLE IF NOT EXISTS CORE.CONTRACTS (
    contract_id    VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id         VARCHAR(36)   NOT NULL,
    customer_id    VARCHAR(36)   NOT NULL,
    contract_name  VARCHAR(500)  NOT NULL,
    contract_value DECIMAL(18,2),
    start_date     DATE,
    end_date       DATE,
    auto_renewal   BOOLEAN       DEFAULT FALSE,
    status         VARCHAR(50)   DEFAULT 'active',
    created_at     TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at     TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (contract_id)
);

CREATE TABLE IF NOT EXISTS CORE.TRANSACTIONS (
    transaction_id   VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id           VARCHAR(36)   NOT NULL,
    customer_id      VARCHAR(36)   NOT NULL,
    transaction_type VARCHAR(50)   NOT NULL,
    amount           DECIMAL(18,2),
    currency         VARCHAR(10)   DEFAULT 'USD',
    status           VARCHAR(50)   DEFAULT 'completed',
    transaction_date DATE          NOT NULL DEFAULT CURRENT_DATE(),
    description      VARCHAR(1000),
    created_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (transaction_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas AI
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS AI.DOCUMENT_CHUNKS (
    chunk_id       VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    document_id    VARCHAR(36)  NOT NULL,
    org_id         VARCHAR(36)  NOT NULL,
    document_name  VARCHAR(500),
    document_type  VARCHAR(100),
    section_title  VARCHAR(500),
    chunk_index    INTEGER      NOT NULL,
    chunk_text     TEXT         NOT NULL,
    char_count     INTEGER,
    created_at     TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (chunk_id)
);

CREATE TABLE IF NOT EXISTS AI.CHURN_SCORES (
    score_id                VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id                  VARCHAR(36)  NOT NULL,
    customer_id             VARCHAR(36)  NOT NULL,
    churn_probability       DECIMAL(5,4) NOT NULL,
    risk_level              VARCHAR(10)  NOT NULL,
    top_drivers             VARIANT,
    recommended_action      VARCHAR(1000),
    expected_revenue_at_risk DECIMAL(18,2),
    model_version           VARCHAR(50),
    scored_at               TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (score_id)
);

CREATE TABLE IF NOT EXISTS AI.REVENUE_FORECAST (
    forecast_id     VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)  NOT NULL,
    forecast_date   DATE         NOT NULL,
    forecast_value  DECIMAL(18,2) NOT NULL,
    lower_bound     DECIMAL(18,2),
    upper_bound     DECIMAL(18,2),
    metric          VARCHAR(100) NOT NULL DEFAULT 'total_revenue',
    model_version   VARCHAR(50),
    generated_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (forecast_id)
);

CREATE TABLE IF NOT EXISTS AI.ANOMALY_ALERTS (
    alert_id        VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)  NOT NULL,
    metric_name     VARCHAR(255) NOT NULL,
    metric_date     DATE         NOT NULL,
    metric_value    DECIMAL(18,4),
    expected_value  DECIMAL(18,4),
    deviation_pct   DECIMAL(8,4),
    is_anomaly      BOOLEAN      NOT NULL DEFAULT FALSE,
    severity        VARCHAR(20)  DEFAULT 'MEDIUM',
    model_version   VARCHAR(50),
    detected_at     TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (alert_id)
);

CREATE TABLE IF NOT EXISTS AI.EMBEDDINGS (
    embedding_id    VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    chunk_id        VARCHAR(36)  NOT NULL,
    org_id          VARCHAR(36)  NOT NULL,
    document_id     VARCHAR(36)  NOT NULL,
    embedding       VECTOR(FLOAT, 1024),
    model_name      VARCHAR(100) DEFAULT 'e5-base-v2',
    created_at      TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (embedding_id)
);

CREATE TABLE IF NOT EXISTS AI.RECOMMENDATIONS (
    recommendation_id   VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id              VARCHAR(36)  NOT NULL,
    entity_id           VARCHAR(36)  NOT NULL,
    entity_type         VARCHAR(50)  DEFAULT 'customer',
    recommendation_type VARCHAR(100) NOT NULL,
    priority            VARCHAR(10)  DEFAULT 'MEDIUM',
    recommendation_text TEXT         NOT NULL,
    expected_impact_usd DECIMAL(18,2),
    confidence_score    DECIMAL(4,3),
    owner_role          VARCHAR(100),
    status              VARCHAR(50)  DEFAULT 'pending',
    is_active           BOOLEAN      DEFAULT TRUE,
    created_at          TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    acted_at            TIMESTAMP_TZ,
    PRIMARY KEY (recommendation_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas Audit
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS AUDIT.ACTION_LOG (
    action_id    VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id       VARCHAR(36)  NOT NULL,
    user_name    VARCHAR(255) NOT NULL,
    role_name    VARCHAR(255),
    action_type  VARCHAR(100) NOT NULL,
    object_type  VARCHAR(50),
    object_id    VARCHAR(36),
    details      VARIANT,
    created_at   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (action_id)
);

CREATE TABLE IF NOT EXISTS AUDIT.CORTEX_ANALYST_LOG (
    query_id      VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id        VARCHAR(36)  NOT NULL,
    user_name     VARCHAR(255) NOT NULL,
    user_role     VARCHAR(255),
    question      TEXT         NOT NULL,
    generated_sql TEXT,
    model_used    VARCHAR(100),
    latency_ms    INTEGER,
    was_helpful   BOOLEAN,
    session_id    VARCHAR(36),
    created_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (query_id)
);

CREATE TABLE IF NOT EXISTS AUDIT.AGENT_CHAT_LOG (
    message_id  VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    session_id  VARCHAR(36)  NOT NULL,
    org_id      VARCHAR(36)  NOT NULL,
    user_name   VARCHAR(255) NOT NULL,
    role        VARCHAR(20)  NOT NULL,
    content     TEXT         NOT NULL,
    tool_name   VARCHAR(100),
    model_used  VARCHAR(100),
    latency_ms  INTEGER,
    created_at  TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (message_id)
);

CREATE TABLE IF NOT EXISTS AUDIT.PROMPT_LOG (
    log_id              VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    session_id          VARCHAR(36),
    org_id              VARCHAR(36)  NOT NULL,
    user_name           VARCHAR(255) NOT NULL,
    role_name           VARCHAR(255) NOT NULL,
    agent_id            VARCHAR(100),
    prompt_text         TEXT         NOT NULL,
    data_sources        VARIANT,
    response_summary    TEXT,
    cortex_tokens_used  INTEGER      DEFAULT 0,
    latency_ms          INTEGER,
    created_at          TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (log_id)
);

CREATE TABLE IF NOT EXISTS AUDIT.DATA_QUALITY_RESULTS (
    result_id    VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id       VARCHAR(36)  NOT NULL,
    table_name   VARCHAR(255) NOT NULL,
    metric_name  VARCHAR(255) NOT NULL,
    metric_value DECIMAL(18,6),
    threshold    DECIMAL(18,6),
    status       VARCHAR(20)  DEFAULT 'PASS',
    measured_at  TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (result_id)
);

CREATE TABLE IF NOT EXISTS AUDIT.ACCESS_LOG (
    access_id     VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id        VARCHAR(36)  NOT NULL,
    user_name     VARCHAR(255) NOT NULL,
    role_name     VARCHAR(255),
    resource_type VARCHAR(100),
    resource_name VARCHAR(500),
    action        VARCHAR(100) NOT NULL,
    success       BOOLEAN      DEFAULT TRUE,
    ip_address    VARCHAR(50),
    created_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (access_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CONFIG.ORG_USER_MAP (
    org_id     VARCHAR(36)  NOT NULL,
    user_name  VARCHAR(255) NOT NULL,
    created_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (org_id, user_name)
);

CREATE TABLE IF NOT EXISTS CONFIG.APP_SETTINGS (
    setting_key   VARCHAR(255)  NOT NULL,
    setting_value VARCHAR(2000) NOT NULL,
    description   TEXT,
    updated_at    TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (setting_key)
);

MERGE INTO CONFIG.APP_SETTINGS t
USING (
    SELECT 'default_llm_model'         AS setting_key, 'mistral-large2'  AS setting_value, 'Modelo LLM padrão para Cortex Complete' AS description
    UNION ALL SELECT 'churn_high_threshold',     '0.7',    'Score acima = risco HIGH'
    UNION ALL SELECT 'churn_medium_threshold',   '0.4',    'Score acima = risco MEDIUM'
    UNION ALL SELECT 'freshness_sla_hours',      '24',     'Horas máx sem refresh antes de alerta'
    UNION ALL SELECT 'audit_retention_days',     '365',    'Retenção de logs de auditoria'
    UNION ALL SELECT 'vertical_pack',            'saas_customer', 'Vertical Pack ativo'
    UNION ALL SELECT 'demo_mode',                'true',   'Usar dataset demo'
    UNION ALL SELECT 'enable_workflow_automation','false', 'Habilitar automações externas'
) s ON t.setting_key = s.setting_key
WHEN NOT MATCHED THEN
    INSERT (setting_key, setting_value, description)
    VALUES (s.setting_key, s.setting_value, s.description);

-- ─────────────────────────────────────────────────────────────────────────────
-- Stages internos
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS CORE.APP_STAGE
    DIRECTORY  = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

CREATE STAGE IF NOT EXISTS CORE.DOC_STAGE
    DIRECTORY  = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

CREATE STAGE IF NOT EXISTS CORE.SEMANTIC_STAGE
    DIRECTORY  = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

CREATE STAGE IF NOT EXISTS CORE.ML_STAGE
    DIRECTORY  = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas de Agente (Agent Workbench)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS AI.AGENT_SESSIONS (
    session_id    VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id        VARCHAR(36)  NOT NULL,
    user_name     VARCHAR(255) NOT NULL,
    agent_type    VARCHAR(100) DEFAULT 'general',
    status        VARCHAR(50)  DEFAULT 'active',
    message_count INTEGER      DEFAULT 0,
    started_at    TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    ended_at      TIMESTAMP_TZ,
    PRIMARY KEY (session_id)
);

CREATE TABLE IF NOT EXISTS AI.AGENT_MESSAGES (
    message_id  VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    session_id  VARCHAR(36)  NOT NULL,
    org_id      VARCHAR(36)  NOT NULL,
    role        VARCHAR(20)  NOT NULL,
    content     TEXT         NOT NULL,
    tool_calls  VARIANT,
    latency_ms  INTEGER,
    created_at  TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (message_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Fila de aprovação humana
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CORE.APPROVAL_QUEUE (
    approval_id  VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id       VARCHAR(36)  NOT NULL,
    action_type  VARCHAR(100) NOT NULL,
    entity_id    VARCHAR(36),
    payload      VARIANT,
    status       VARCHAR(50)  DEFAULT 'pending',
    requested_by VARCHAR(255),
    approved_by  VARCHAR(255),
    created_at   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    decided_at   TIMESTAMP_TZ,
    PRIMARY KEY (approval_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- MART: visões consolidadas para Streamlit
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW MART.CUSTOMER_360 AS
WITH ticket_agg AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                                AS total_tickets,
        SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END)                      AS open_tickets,
        SUM(CASE WHEN status = 'open'
                  AND priority IN ('urgent','high') THEN 1 ELSE 0 END)        AS critical_open_tickets,
        SUM(CASE WHEN sla_breach = TRUE THEN 1 ELSE 0 END)                    AS sla_breaches,
        AVG(sentiment_score)                                                    AS avg_sentiment_score
    FROM CORE.TICKETS
    GROUP BY customer_id, org_id
),
latest_sentiment AS (
    SELECT customer_id, org_id, sentiment_label
    FROM CORE.TICKETS
    WHERE sentiment_label IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id, org_id ORDER BY created_at DESC) = 1
),
usage_30d AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                           AS events_30d,
        COUNT(DISTINCT DATE(occurred_at))                  AS active_days_30d,
        COUNT(DISTINCT feature_name)                       AS distinct_features_used,
        MAX(occurred_at)                                   AS last_activity_at,
        DATEDIFF('day', MAX(occurred_at), CURRENT_TIMESTAMP()) AS days_since_last_activity
    FROM CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
),
usage_7d AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                          AS events_7d,
        COUNT(DISTINCT DATE(occurred_at)) AS active_days_7d
    FROM CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
),
agent_30d AS (
    SELECT customer_id, org_id, COUNT(*) AS agent_invocations_30d
    FROM CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
      AND event_type = 'agent_invocation'
    GROUP BY customer_id, org_id
)
SELECT
    c.customer_id,
    c.org_id,
    c.name,
    c.name                                                              AS customer_name,
    c.email,
    c.segment,
    c.region,
    c.industry,
    c.status,
    c.lifecycle_stage,
    c.nps_score,
    c.arr,
    c.mrr,
    c.contract_end_date,
    c.customer_since,
    c.updated_at,
    -- Churn
    cs.churn_probability,
    cs.risk_level                                                       AS churn_risk_level,
    cs.expected_revenue_at_risk,
    cs.recommended_action                                               AS churn_recommended_action,
    cs.top_drivers,
    cs.scored_at,
    ROUND((1.0 - COALESCE(cs.churn_probability, 0.5)) * 100, 0)       AS health_score,
    -- Nearest renewal from active subscriptions
    (SELECT MIN(s.renewal_date)
     FROM CORE.SUBSCRIPTIONS s
     WHERE s.customer_id = c.customer_id
       AND s.org_id = c.org_id
       AND s.renewal_date >= CURRENT_DATE()
       AND s.status = 'active')                                         AS nearest_renewal_date,
    -- Ticket metrics
    COALESCE(ta.total_tickets, 0)                                       AS total_tickets,
    COALESCE(ta.open_tickets, 0)                                        AS open_tickets,
    COALESCE(ta.critical_open_tickets, 0)                               AS critical_open_tickets,
    COALESCE(ta.sla_breaches, 0)                                        AS sla_breaches,
    ta.avg_sentiment_score,
    ls.sentiment_label,
    -- Usage metrics (30d)
    COALESCE(u30.events_30d, 0)                                         AS events_30d,
    COALESCE(u30.active_days_30d, 0)                                    AS active_days_30d,
    COALESCE(u30.distinct_features_used, 0)                             AS distinct_features_used,
    u30.last_activity_at,
    COALESCE(u30.days_since_last_activity, 999)                         AS days_since_last_activity,
    -- Usage metrics (7d)
    COALESCE(u7.events_7d, 0)                                           AS events_7d,
    COALESCE(u7.active_days_7d, 0)                                      AS active_days_7d,
    -- Agent usage
    COALESCE(ag.agent_invocations_30d, 0)                               AS agent_invocations_30d,
    -- Usage trend: compare 7d rate vs 30d rate
    CASE
        WHEN COALESCE(u30.events_30d, 0) = 0 THEN 'no_data'
        WHEN COALESCE(u7.events_7d, 0) > COALESCE(u30.events_30d, 0) * 0.35 THEN 'up'
        WHEN COALESCE(u7.events_7d, 0) < COALESCE(u30.events_30d, 0) * 0.15 THEN 'down'
        ELSE 'stable'
    END                                                                  AS usage_trend
FROM CORE.CUSTOMERS c
LEFT JOIN (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY scored_at DESC) AS rn
    FROM AI.CHURN_SCORES
) cs ON c.customer_id = cs.customer_id AND cs.rn = 1
LEFT JOIN ticket_agg  ta  ON c.customer_id = ta.customer_id  AND c.org_id = ta.org_id
LEFT JOIN latest_sentiment ls ON c.customer_id = ls.customer_id AND c.org_id = ls.org_id
LEFT JOIN usage_30d   u30 ON c.customer_id = u30.customer_id AND c.org_id = u30.org_id
LEFT JOIN usage_7d    u7  ON c.customer_id = u7.customer_id  AND c.org_id = u7.org_id
LEFT JOIN agent_30d   ag  ON c.customer_id = ag.customer_id  AND c.org_id = ag.org_id;

CREATE OR REPLACE VIEW AI.V_CONTRACT_INTELLIGENCE AS
SELECT
    d.document_id,
    d.org_id,
    d.document_name,
    d.document_type,
    d.processing_status,
    d.summary,
    d.created_at,
    COUNT(ch.chunk_id) AS chunk_count
FROM CORE.DOCUMENTS d
LEFT JOIN AI.DOCUMENT_CHUNKS ch ON d.document_id = ch.document_id
WHERE d.document_type IN ('contract', 'sla', 'amendment', 'addendum')
GROUP BY d.document_id, d.org_id, d.document_name, d.document_type,
         d.processing_status, d.summary, d.created_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- Document AI — SP_PROCESS_DOCUMENT (CLASSIFY + SUMMARIZE + COMPLETE)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE AI.SP_PROCESS_DOCUMENT(
    p_document_id VARCHAR,
    p_org_id      VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'process_document'
AS $$
import json

EXTRACTABLE_TYPES = {'contract', 'sla', 'amendment'}
CLASSIFICATION_LABELS = ['contract', 'sla', 'amendment', 'invoice', 'proposal', 'nda', 'other']

EXTRACTION_PROMPT = """Analise o documento abaixo e extraia as informações no formato JSON.
Responda APENAS com o JSON, sem texto adicional.

Formato:
{{
  "effective_date": "YYYY-MM-DD ou null",
  "expiration_date": "YYYY-MM-DD ou null",
  "total_value": "valor ou null",
  "total_value_currency": "USD/BRL/EUR ou null",
  "auto_renewal": true/false/null,
  "governing_law": "jurisdição ou null",
  "parties": ["lista de partes"],
  "payment_terms": "descrição ou null"
}}

DOCUMENTO:
{text}"""


def _safe(v, n=100000):
    return (str(v)[:n] if v else '').replace("'", "''")


def process_document(session, p_document_id: str, p_org_id: str) -> str:
    try:
        rows = session.sql(f"""
            SELECT document_type, extracted_text FROM CORE.DOCUMENTS
            WHERE document_id = '{p_document_id}' AND org_id = '{p_org_id}' LIMIT 1
        """).collect()
        if not rows:
            return f"ERROR: document '{p_document_id}' not found"

        doc_type = (rows[0]['DOCUMENT_TYPE'] or '').lower()
        raw_text = rows[0]['EXTRACTED_TEXT'] or ''
        if not raw_text:
            chunks = session.sql(f"""
                SELECT chunk_text FROM AI.DOCUMENT_CHUNKS
                WHERE document_id = '{p_document_id}' ORDER BY chunk_index
            """).collect()
            raw_text = ' '.join(r['CHUNK_TEXT'] for r in chunks if r['CHUNK_TEXT'])
        if not raw_text:
            return f"ERROR: no text for document '{p_document_id}'"

        steps = []

        # 1. CLASSIFY
        labels_sql = 'ARRAY_CONSTRUCT(' + ', '.join(f"'{l}'" for l in CLASSIFICATION_LABELS) + ')'
        cr = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.CLASSIFY_TEXT('{_safe(raw_text, 2000)}', {labels_sql}) AS r
        """).collect()
        label, score = doc_type, 0.0
        if cr and cr[0]['R']:
            rd = json.loads(cr[0]['R']) if isinstance(cr[0]['R'], str) else cr[0]['R']
            label = (rd.get('label') or doc_type).lower()
            score = float(rd.get('score') or 0.0)
        steps.append(f'classify={label}({score:.2f})')

        # 2. SUMMARIZE
        sr = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.SUMMARIZE('{_safe(raw_text, 80000)}') AS s
        """).collect()
        ai_summary = (sr[0]['S'] or '') if sr else ''
        steps.append('summarize=ok' if ai_summary else 'summarize=empty')

        # 3. COMPLETE — structured extraction for contracts/SLAs
        ef_json = None
        eff_type = label if score >= 0.6 else doc_type
        if eff_type in EXTRACTABLE_TYPES:
            prompt = _safe(EXTRACTION_PROMPT.format(text=raw_text[:12000]), 20000)
            cr2 = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', '{prompt}') AS j
            """).collect()
            if cr2 and cr2[0]['J']:
                raw_j = cr2[0]['J'].strip().strip('```').strip()
                safe_j = raw_j.replace("'", "''")
                ok = session.sql(f"SELECT TRY_PARSE_JSON('{safe_j}') AS p").collect()
                if ok and ok[0]['P'] is not None:
                    ef_json = safe_j
                    steps.append('extract=ok')
                else:
                    steps.append('extract=parse_failed')
            else:
                steps.append('extract=no_response')
        else:
            steps.append(f'extract=skipped({eff_type})')

        # 4. Persist
        safe_sum  = _safe(ai_summary)
        safe_lbl  = label.replace("'", "''")
        doc_type_set = f"document_type = '{safe_lbl}'," if score >= 0.6 else ''
        ef_set = f"extracted_fields = TRY_PARSE_JSON('{ef_json}')," if ef_json else ''

        session.sql(f"""
            UPDATE CORE.DOCUMENTS SET
                {doc_type_set}
                document_category = '{safe_lbl}',
                document_summary  = '{safe_sum}',
                summary           = '{safe_sum}',
                {ef_set}
                processing_status = 'completed',
                processed_at      = CURRENT_TIMESTAMP()
            WHERE document_id = '{p_document_id}' AND org_id = '{p_org_id}'
        """).collect()

        return 'OK: ' + ' | '.join(steps)

    except Exception as e:
        try:
            session.sql(f"""
                UPDATE CORE.DOCUMENTS SET processing_status = 'failed',
                    processed_at = CURRENT_TIMESTAMP()
                WHERE document_id = '{p_document_id}' AND org_id = '{p_org_id}'
            """).collect()
        except Exception:
            pass
        return f'ERROR: {e}'
$$;

CREATE OR REPLACE PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(p_org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, p_org_id: str) -> str:
    org_filter = '' if p_org_id == 'ALL' else f"AND org_id = '{p_org_id}'"
    rows = session.sql(f"""
        SELECT document_id, org_id FROM CORE.DOCUMENTS
        WHERE processing_status IN ('pending', 'completed')
          AND (extracted_text IS NOT NULL OR document_id IN (
              SELECT DISTINCT document_id FROM AI.DOCUMENT_CHUNKS
          ))
          AND (document_category IS NULL OR document_category = '')
          {org_filter}
        LIMIT 50
    """).collect()

    ok, fail = 0, 0
    for r in rows:
        res = session.sql(f"""
            CALL AI.SP_PROCESS_DOCUMENT('{r['DOCUMENT_ID']}', '{r['ORG_ID']}')
        """).collect()
        if res and str(res[0][0]).startswith('OK'):
            ok += 1
        else:
            fail += 1
    return f'OK: {ok} enriched, {fail} failed'
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Dynamic Tables — MART e AI
-- Refresh declarativo: Snowflake recalcula cada DT automaticamente.
-- Requer que NEXUS_COMPUTE_WH exista no account do consumer.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH
    TARGET_LAG  = '1 hour'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
AS
WITH
latest_churn AS (
    SELECT customer_id, org_id, churn_probability, risk_level,
           expected_revenue_at_risk, recommended_action, scored_at
    FROM AI.CHURN_SCORES
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id, org_id ORDER BY scored_at DESC) = 1
),
open_ticket_counts AS (
    SELECT customer_id, org_id,
        COUNT(*) AS open_tickets,
        COUNT(CASE WHEN priority IN ('urgent', 'high') THEN 1 END) AS critical_open_tickets,
        COUNT(CASE WHEN sla_breach = TRUE THEN 1 END) AS sla_breaches
    FROM CORE.TICKETS
    WHERE status = 'open'
    GROUP BY customer_id, org_id
),
usage_30d AS (
    SELECT customer_id, org_id,
        COUNT(*) AS events_30d,
        COUNT(DISTINCT DATE(occurred_at)) AS active_days_30d,
        COUNT(DISTINCT feature_name) AS distinct_features_30d,
        MAX(occurred_at) AS last_activity_at
    FROM CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
)
SELECT
    c.customer_id, c.org_id,
    c.name AS customer_name, c.name AS name,
    c.segment, c.lifecycle_stage,
    c.arr, c.mrr, c.nps_score, c.contract_end_date,
    DATEDIFF('day', CURRENT_DATE(), c.contract_end_date) AS days_to_renewal,
    COALESCE(cs.churn_probability, 0.5)       AS churn_probability,
    COALESCE(cs.churn_probability, 0.5)       AS churn_risk_score,
    COALESCE(cs.risk_level, 'UNKNOWN')        AS churn_risk_level,
    COALESCE(cs.risk_level, 'UNKNOWN')        AS risk_level,
    COALESCE(cs.expected_revenue_at_risk, 0)  AS expected_revenue_at_risk,
    cs.recommended_action                      AS churn_recommended_action,
    cs.scored_at                               AS churn_scored_at,
    COALESCE(t.open_tickets, 0)               AS open_tickets,
    COALESCE(t.open_tickets, 0)               AS open_ticket_count,
    COALESCE(t.critical_open_tickets, 0)      AS critical_open_tickets,
    COALESCE(t.sla_breaches, 0)               AS sla_breaches,
    COALESCE(u.events_30d, 0)                 AS events_30d,
    COALESCE(u.active_days_30d, 0)            AS active_days_30d,
    COALESCE(u.distinct_features_30d, 0)      AS distinct_features_30d,
    u.last_activity_at,
    DATEDIFF('day', u.last_activity_at, CURRENT_TIMESTAMP()) AS days_since_last_activity,
    ROUND((1 - COALESCE(cs.churn_probability, 0.5)) * 100, 0) AS health_score,
    CURRENT_TIMESTAMP() AS refreshed_at
FROM CORE.CUSTOMERS c
LEFT JOIN latest_churn       cs ON c.customer_id = cs.customer_id AND c.org_id = cs.org_id
LEFT JOIN open_ticket_counts  t ON c.customer_id = t.customer_id  AND c.org_id = t.org_id
LEFT JOIN usage_30d           u ON c.customer_id = u.customer_id  AND c.org_id = u.org_id;

CREATE OR REPLACE DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS
    TARGET_LAG  = '1 hour'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
AS
WITH active_recommendations AS (
    SELECT org_id, COUNT(*) AS open_recommendations,
           SUM(expected_impact_usd) AS total_expected_impact_usd
    FROM AI.RECOMMENDATIONS
    WHERE is_active = TRUE AND status = 'pending'
    GROUP BY org_id
)
SELECT
    h.org_id,
    COUNT(*) AS customer_count,
    COUNT(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN 1 END) AS active_count,
    COUNT(CASE WHEN h.churn_risk_level = 'HIGH' THEN 1 END) AS at_risk_count,
    COUNT(CASE WHEN h.lifecycle_stage IN ('churned', 'cancelled') THEN 1 END) AS churned_count,
    SUM(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN COALESCE(h.arr, 0) ELSE 0 END) AS total_arr,
    SUM(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN COALESCE(h.mrr, 0) ELSE 0 END) AS total_mrr,
    ROUND(AVG(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN h.nps_score END), 1) AS avg_nps,
    SUM(CASE WHEN h.churn_risk_level IN ('HIGH', 'MEDIUM') THEN COALESCE(h.expected_revenue_at_risk, 0) ELSE 0 END) AS arr_at_risk,
    SUM(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
              AND h.contract_end_date IS NOT NULL
              AND h.days_to_renewal BETWEEN 0 AND 90
             THEN COALESCE(h.arr, 0) ELSE 0 END) AS renewal_90d_arr,
    COALESCE(r.open_recommendations, 0)       AS open_recommendations,
    COALESCE(r.total_expected_impact_usd, 0)  AS total_expected_impact_usd,
    ROUND(AVG(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN h.health_score END), 1) AS avg_health_score,
    CURRENT_TIMESTAMP() AS refreshed_at
FROM MART.DT_CUSTOMER_HEALTH h
LEFT JOIN active_recommendations r ON h.org_id = r.org_id
GROUP BY h.org_id, r.open_recommendations, r.total_expected_impact_usd;

-- NOTA: DT_REVENUE_MOVEMENT (mês/tipo/transação) é declarada mais abaixo — é o
-- schema canônico consumido por 11_Sales_Intelligence.py e revenue_opportunity_model.yaml.
-- Uma definição anterior com granularidade diária (new_arr/expansion_arr/contraction_arr/
-- net_arr) nunca chegou a ser consumida por nenhuma página ou modelo semântico; foi
-- removida para eliminar a duplicata de CREATE OR REPLACE que silenciosamente a sobrescrevia.

CREATE OR REPLACE DYNAMIC TABLE AI.DT_SUPPORT_INTELLIGENCE
    TARGET_LAG  = '30 minutes'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
AS
SELECT
    org_id,
    COUNT(*) AS total_tickets,
    COUNT(CASE WHEN status = 'open' THEN 1 END)     AS open_tickets,
    COUNT(CASE WHEN status = 'resolved' THEN 1 END) AS resolved_tickets,
    COUNT(CASE WHEN status = 'open' AND priority IN ('urgent', 'high') THEN 1 END) AS critical_tickets,
    COUNT(CASE WHEN sla_breach = TRUE THEN 1 END) AS sla_breached_count,
    ROUND(COUNT(CASE WHEN sla_breach = TRUE THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS sla_breach_rate_pct,
    ROUND(AVG(CASE WHEN resolved_at IS NOT NULL THEN DATEDIFF('minute', created_at, resolved_at) / 60.0 END), 2) AS avg_resolution_hours,
    ROUND(AVG(CASE WHEN status = 'open' THEN sentiment_score END), 3) AS avg_open_sentiment,
    ROUND(AVG(sentiment_score), 3) AS avg_sentiment,
    COUNT(CASE WHEN sentiment_label = 'positive' THEN 1 END) AS positive_tickets,
    COUNT(CASE WHEN sentiment_label = 'neutral'  THEN 1 END) AS neutral_tickets,
    COUNT(CASE WHEN sentiment_label = 'negative' THEN 1 END) AS negative_tickets,
    COUNT(CASE WHEN created_at >= DATEADD('day', -7, CURRENT_TIMESTAMP()) THEN 1 END) AS tickets_trend_7d,
    COUNT(CASE WHEN status = 'open' AND DATEDIFF('hour', created_at, CURRENT_TIMESTAMP()) > 48 THEN 1 END) AS stale_open_tickets,
    MIN(CASE WHEN status = 'open' THEN created_at END) AS oldest_open_ticket_at,
    CURRENT_TIMESTAMP() AS refreshed_at
FROM CORE.TICKETS
GROUP BY org_id;

-- DT_REVENUE_MOVEMENT precisa ser criada antes da seção "Grants para Application
-- Roles" mais abaixo, que já a referencia — movida para aqui (junto das outras
-- Dynamic Tables) para respeitar a ordem de dependência.
CREATE OR REPLACE DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Movimento de receita — New, Expansion, Churn por mês'
AS
SELECT
    org_id,
    DATE_TRUNC('month', transaction_date)           AS month,
    transaction_type,
    COUNT(*)                                        AS transaction_count,
    SUM(amount)                                     AS total_amount,
    AVG(amount)                                     AS avg_amount
FROM CORE.TRANSACTIONS
GROUP BY org_id, DATE_TRUNC('month', transaction_date), transaction_type;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cortex Search Service — AI.DOC_SEARCH
-- Semantic search over document chunks (used by AI Chat + Document Intelligence)
-- ─────────────────────────────────────────────────────────────────────────────

-- Tolerante a contas/roles sem acesso à função de embedding do Cortex Search
-- (erro observado: "Current role does not have access to Cortex embedding
-- function snowflake.cortex.embed_text_768"), mesmo tratamento já dado pelo
-- IGNORABLE list do path de deploy direto ("cortex search service").
EXECUTE IMMEDIATE $$
BEGIN
    CREATE OR REPLACE CORTEX SEARCH SERVICE AI.DOC_SEARCH
        ON chunk_text
        ATTRIBUTES org_id, document_id, document_name, document_type
        WAREHOUSE = NEXUS_COMPUTE_WH
        TARGET_LAG = '1 hour'
        COMMENT = 'Semantic search sobre chunks de documentos NEXUS — contratos, relatórios, manuais'
    AS (
        SELECT
            chunk_id,
            org_id,
            document_id,
            document_name,
            document_type,
            chunk_text,
            chunk_index,
            COALESCE(section_title, '') AS section_title
        FROM AI.DOCUMENT_CHUNKS
    );
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cortex Search Service — AI.CONTRACT_SEARCH
-- Semantic search dedicado a contratos e SLAs
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW AI.CONTRACT_CHUNKS_V AS
SELECT
    ch.chunk_id,
    ch.document_id,
    ch.chunk_text,
    ch.chunk_index,
    COALESCE(ch.section_title, '') AS section_title,
    d.document_name                AS contract_name,
    d.document_type,
    d.org_id,
    d.entity_id                    AS customer_id,
    c.name                         AS customer_name,
    d.contract_type,
    d.contract_value_usd,
    d.start_date,
    d.end_date,
    d.auto_renewal,
    d.governing_law,
    d.ai_summary                   AS contract_summary
FROM AI.DOCUMENT_CHUNKS ch
JOIN CORE.DOCUMENTS d  ON ch.document_id = d.document_id
LEFT JOIN CORE.CUSTOMERS c ON d.entity_id = c.customer_id AND d.org_id = c.org_id
WHERE d.document_type IN ('contract', 'sla', 'amendment', 'addendum')
  AND ch.chunk_text IS NOT NULL;

EXECUTE IMMEDIATE $$
BEGIN
    CREATE OR REPLACE CORTEX SEARCH SERVICE AI.CONTRACT_SEARCH
        ON chunk_text
        ATTRIBUTES
            document_id, contract_name, customer_name, customer_id, org_id,
            document_type, section_title, contract_type, contract_value_usd,
            start_date, end_date, auto_renewal, governing_law, contract_summary
        WAREHOUSE = NEXUS_COMPUTE_WH
        TARGET_LAG = '1 hour'
        COMMENT = 'Semantic search sobre contratos e SLAs — Contract Intelligence NEXUS'
    AS (SELECT * FROM AI.CONTRACT_CHUNKS_V);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants para Application Roles
-- ─────────────────────────────────────────────────────────────────────────────

-- NEXUS_VIEWER — leitura de dashboards
GRANT USAGE ON SCHEMA MART       TO APPLICATION ROLE NEXUS_VIEWER;
GRANT USAGE ON SCHEMA AI         TO APPLICATION ROLE NEXUS_VIEWER;
GRANT USAGE ON SCHEMA CONFIG     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON ALL TABLES IN SCHEMA MART   TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON ALL TABLES IN SCHEMA AI     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE CONFIG.APP_SETTINGS   TO APPLICATION ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE AUDIT.ACTION_LOG      TO APPLICATION ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE AUDIT.CORTEX_ANALYST_LOG TO APPLICATION ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE AUDIT.AGENT_CHAT_LOG  TO APPLICATION ROLE NEXUS_VIEWER;

-- NEXUS_ANALYST — tudo de VIEWER + dados CORE + execução de SPs de leitura
GRANT USAGE ON SCHEMA CORE       TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA CORE   TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA AUDIT  TO APPLICATION ROLE NEXUS_ANALYST;

-- NEXUS_ADMIN — tudo
GRANT USAGE  ON SCHEMA GOVERNANCE TO APPLICATION ROLE NEXUS_ADMIN;
GRANT USAGE  ON SCHEMA AUDIT      TO APPLICATION ROLE NEXUS_ADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON ALL TABLES IN SCHEMA CONFIG     TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON ALL TABLES IN SCHEMA AUDIT      TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON STAGE CORE.DOC_STAGE            TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON STAGE CORE.SEMANTIC_STAGE       TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON STAGE CORE.ML_STAGE             TO APPLICATION ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cortex privileges
-- ─────────────────────────────────────────────────────────────────────────────

-- NOTE: GRANT DATABASE ROLE from external DB is not supported inside setup_script.
-- Apply these after app install via SnowSQL or Snowsight as ACCOUNTADMIN:
--   GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION ROLE <app>.NEXUS_VIEWER;
--   GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION ROLE <app>.NEXUS_ANALYST;
--   GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO APPLICATION ROLE <app>.NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants adicionais para AUDIT.PROMPT_LOG
-- ─────────────────────────────────────────────────────────────────────────────

GRANT INSERT ON TABLE AUDIT.PROMPT_LOG TO APPLICATION ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE AUDIT.PROMPT_LOG TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON TABLE AUDIT.PROMPT_LOG TO APPLICATION ROLE NEXUS_ADMIN;

-- Grants para tabelas adicionais
GRANT SELECT ON VIEW  MART.CUSTOMER_360             TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON VIEW  AI.V_CONTRACT_INTELLIGENCE    TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT, INSERT ON TABLE AI.AGENT_SESSIONS     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT, INSERT ON TABLE AI.AGENT_MESSAGES     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT, INSERT ON TABLE CORE.APPROVAL_QUEUE   TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON TABLE  CORE.CONTRACTS              TO APPLICATION ROLE NEXUS_ANALYST;
GRANT ALL    ON TABLE  CORE.CONTRACTS              TO APPLICATION ROLE NEXUS_ADMIN;
GRANT SELECT ON TABLE  CORE.TRANSACTIONS           TO APPLICATION ROLE NEXUS_ANALYST;
GRANT ALL    ON TABLE  CORE.TRANSACTIONS           TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON TABLE  CORE.APPROVAL_QUEUE          TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON TABLE  AI.RECOMMENDATIONS           TO APPLICATION ROLE NEXUS_ANALYST;

-- Cortex Search Services — tolerante caso a criação tenha sido pulada acima
-- (conta/role sem acesso à função de embedding do Cortex Search)
EXECUTE IMMEDIATE $$
BEGIN
    GRANT USAGE ON CORTEX SEARCH SERVICE AI.DOC_SEARCH      TO APPLICATION ROLE NEXUS_ADMIN;
    GRANT USAGE ON CORTEX SEARCH SERVICE AI.DOC_SEARCH      TO APPLICATION ROLE NEXUS_ANALYST;
    GRANT USAGE ON CORTEX SEARCH SERVICE AI.DOC_SEARCH      TO APPLICATION ROLE NEXUS_VIEWER;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

EXECUTE IMMEDIATE $$
BEGIN
    GRANT USAGE ON CORTEX SEARCH SERVICE AI.CONTRACT_SEARCH TO APPLICATION ROLE NEXUS_ADMIN;
    GRANT USAGE ON CORTEX SEARCH SERVICE AI.CONTRACT_SEARCH TO APPLICATION ROLE NEXUS_ANALYST;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
GRANT SELECT ON VIEW AI.CONTRACT_CHUNKS_V               TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON VIEW AI.CONTRACT_CHUNKS_V               TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON VIEW AI.CONTRACT_CHUNKS_V               TO APPLICATION ROLE NEXUS_ADMIN;

-- Document AI procedures
GRANT USAGE ON PROCEDURE AI.SP_PROCESS_DOCUMENT(VARCHAR, VARCHAR)
    TO APPLICATION ROLE NEXUS_ADMIN;
GRANT USAGE ON PROCEDURE AI.SP_PROCESS_DOCUMENT(VARCHAR, VARCHAR)
    TO APPLICATION ROLE NEXUS_ANALYST;
GRANT USAGE ON PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(VARCHAR)
    TO APPLICATION ROLE NEXUS_ADMIN;

-- Dynamic Tables
GRANT SELECT ON DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH      TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS       TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE AI.DT_SUPPORT_INTELLIGENCE   TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH      TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS       TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT     TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE AI.DT_SUPPORT_INTELLIGENCE   TO APPLICATION ROLE NEXUS_ANALYST;
GRANT ALL    ON DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH      TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS       TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT     TO APPLICATION ROLE NEXUS_ADMIN;
GRANT ALL    ON DYNAMIC TABLE AI.DT_SUPPORT_INTELLIGENCE   TO APPLICATION ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Streamlit UI (referenciado por manifest.yml como default_streamlit)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Reference callback — chamado pelo framework ao consumer registrar objetos externos
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.REGISTER_REFERENCE(ref_name VARCHAR, operation VARCHAR, ref_or_alias VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    CASE (operation)
        WHEN 'ADD'    THEN SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'REMOVE' THEN SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
        WHEN 'CLEAR'  THEN SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
    END CASE;
    RETURN 'OK';
END;
$$;

GRANT USAGE ON PROCEDURE CORE.REGISTER_REFERENCE(VARCHAR, VARCHAR, VARCHAR)
    TO APPLICATION ROLE NEXUS_ADMIN;

CREATE OR REPLACE STREAMLIT CORE.NEXUS_UI
    FROM '/streamlit'
    MAIN_FILE = 'Home.py';

GRANT USAGE ON STREAMLIT CORE.NEXUS_UI TO APPLICATION ROLE NEXUS_VIEWER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Versioning
-- ─────────────────────────────────────────────────────────────────────────────

MERGE INTO CONFIG.APP_SETTINGS t
USING (SELECT 'app_version' AS setting_key, '1.0.0' AS setting_value, 'NEXUS AI DataOps version installed' AS description) s
ON t.setting_key = s.setting_key
WHEN NOT MATCHED THEN
    INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description)
WHEN MATCHED THEN
    UPDATE SET setting_value = '1.0.0', updated_at = CURRENT_TIMESTAMP();

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P0: Multi-tenancy, Row Access Policies e isolamento por org_id
-- ─────────────────────────────────────────────────────────────────────────────

-- Extende CONFIG.ORG_USER_MAP com coluna role (idempotente)
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CONFIG.ORG_USER_MAP ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'analyst';
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- Seed: usuários demo (idempotente)
MERGE INTO CONFIG.ORG_USER_MAP t
USING (
    SELECT 'ORG-DEMO-001' AS org_id, 'NEXUS_ADMIN'   AS user_name, 'admin'    AS role UNION ALL
    SELECT 'ORG-DEMO-001',            'NEXUS_ANALYST', 'analyst'
) s ON t.org_id = s.org_id AND t.user_name = s.user_name
WHEN NOT MATCHED THEN INSERT (org_id, user_name, role) VALUES (s.org_id, s.user_name, s.role)
WHEN MATCHED THEN UPDATE SET role = s.role;

-- CONFIG.DATA_SOURCES — rastreia quais referências o consumer mapeou
CREATE TABLE IF NOT EXISTS CONFIG.DATA_SOURCES (
    source_name  VARCHAR(100)   NOT NULL,
    is_active    BOOLEAN        DEFAULT FALSE,
    mapped_at    TIMESTAMP_TZ,
    PRIMARY KEY  (source_name)
);

MERGE INTO CONFIG.DATA_SOURCES t
USING (
    SELECT 'customer_table'     AS source_name, FALSE AS is_active UNION ALL
    SELECT 'transactions_table', FALSE UNION ALL
    SELECT 'events_table',       FALSE
) s ON t.source_name = s.source_name
WHEN NOT MATCHED THEN INSERT (source_name, is_active) VALUES (s.source_name, s.is_active);

-- Row Access Policy — filtra por org_id usando CONFIG.ORG_USER_MAP
-- IF NOT EXISTS (não OR REPLACE): Snowflake recusa substituir uma policy
-- já associada a tabelas ("cannot be dropped/replaced as it is associated
-- with one or more entities") — em upgrades a policy já está anexada às
-- ~18 tabelas abaixo desde o install anterior.
CREATE ROW ACCESS POLICY IF NOT EXISTS CORE.RAP_ORG_ISOLATION
  AS (row_org_id VARCHAR) RETURNS BOOLEAN ->
  (
    -- Permite acesso se usuário está mapeado para este org_id
    EXISTS (
      SELECT 1 FROM CONFIG.ORG_USER_MAP m
      WHERE m.user_name = CURRENT_USER()
        AND m.org_id    = row_org_id
    )
    -- Fallback: se tabela de mapeamento vazia, permite tudo (estado inicial do install)
    OR NOT EXISTS (SELECT 1 FROM CONFIG.ORG_USER_MAP)
  );

-- Aplicar RAP em todas as tabelas que contêm org_id
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.CUSTOMERS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.SUBSCRIPTIONS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.TICKETS       ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.PRODUCT_EVENTS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.DOCUMENTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.TRANSACTIONS  ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.CONTRACTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.CHURN_SCORES    ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.RECOMMENDATIONS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.DOCUMENT_CHUNKS  ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.REVENUE_FORECAST ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.ANOMALY_ALERTS   ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.EMBEDDINGS       ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Data Metric Functions — qualidade de dados (recurso de Snowflake Enterprise
-- Edition). Empacotado num procedure Python com try/except por statement para
-- não quebrar o install inteiro em contas Standard Edition, onde DATA METRIC
-- FUNCTION não existe — cada DDL que falhar é apenas reportado como SKIPPED.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.SP_SETUP_DATA_QUALITY_DMFS()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def _try(session, sql, label, results):
    try:
        session.sql(sql).collect()
        results.append(f"{label}:OK")
    except Exception as e:
        results.append(f"{label}:SKIPPED({type(e).__name__})")

def run(session):
    results = []

    _try(session, """
        CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT(ARG_T TABLE(COL_1 VARCHAR))
        RETURNS NUMBER AS 'SELECT COUNT_IF(COL_1 IS NULL) FROM ARG_T'
    """, "CREATE_DMF_NULL_COUNT", results)

    _try(session, """
        CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_FRESHNESS_HOURS(ARG_T TABLE(TS_COL TIMESTAMP_TZ))
        RETURNS NUMBER AS
        'SELECT DATEDIFF(''hour'', ''1970-01-01''::TIMESTAMP_TZ,
                        COALESCE(MAX(TS_COL), ''1970-01-01''::TIMESTAMP_TZ))
         FROM ARG_T'
    """, "CREATE_DMF_FRESHNESS_HOURS", results)

    _try(session, """
        CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_DUPLICATE_COUNT(ARG_T TABLE(KEY_COL VARCHAR))
        RETURNS NUMBER AS 'SELECT COUNT(*) - COUNT(DISTINCT KEY_COL) FROM ARG_T'
    """, "CREATE_DMF_DUPLICATE_COUNT", results)

    attachments = [
        ("CORE.CUSTOMERS SET DATA_METRIC_SCHEDULE = '60 MINUTE'",
         "ALTER TABLE CORE.CUSTOMERS SET DATA_METRIC_SCHEDULE = '60 MINUTE'"),
        ("CUSTOMERS.customer_id NULL_COUNT",
         "ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (customer_id)"),
        ("CUSTOMERS.org_id NULL_COUNT",
         "ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (org_id)"),
        ("CUSTOMERS.email NULL_COUNT",
         "ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (email)"),
        ("CUSTOMERS.customer_id DUPLICATE_COUNT",
         "ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_DUPLICATE_COUNT ON (customer_id)"),
        ("CUSTOMERS.created_at FRESHNESS_HOURS",
         "ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_FRESHNESS_HOURS ON (created_at)"),
        ("CORE.TRANSACTIONS SET DATA_METRIC_SCHEDULE = '60 MINUTE'",
         "ALTER TABLE CORE.TRANSACTIONS SET DATA_METRIC_SCHEDULE = '60 MINUTE'"),
        ("TRANSACTIONS.transaction_id NULL_COUNT",
         "ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (transaction_id)"),
        ("TRANSACTIONS.customer_id NULL_COUNT",
         "ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (customer_id)"),
        ("TRANSACTIONS.created_at FRESHNESS_HOURS",
         "ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_FRESHNESS_HOURS ON (created_at)"),
        ("CORE.TICKETS SET DATA_METRIC_SCHEDULE = '60 MINUTE'",
         "ALTER TABLE CORE.TICKETS SET DATA_METRIC_SCHEDULE = '60 MINUTE'"),
        ("TICKETS.ticket_id NULL_COUNT",
         "ALTER TABLE CORE.TICKETS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT ON (ticket_id)"),
        ("TICKETS.created_at FRESHNESS_HOURS",
         "ALTER TABLE CORE.TICKETS ADD DATA METRIC FUNCTION GOVERNANCE.DMF_FRESHNESS_HOURS ON (created_at)"),
    ]
    for label, sql in attachments:
        _try(session, sql, label, results)

    return " | ".join(results)
$$;

CALL CORE.SP_SETUP_DATA_QUALITY_DMFS();

GRANT USAGE ON PROCEDURE CORE.SP_SETUP_DATA_QUALITY_DMFS() TO APPLICATION ROLE NEXUS_ADMIN;

CREATE OR REPLACE VIEW GOVERNANCE.V_DMF_REGISTRATIONS AS
SELECT
    ref_entity_name                      AS table_fqn,
    SPLIT_PART(ref_entity_name, '.', 2) AS table_schema,
    SPLIT_PART(ref_entity_name, '.', 3) AS table_name,
    metric_name, schedule, schedule_status
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE', REF_ENTITY_NAME => 'CORE.CUSTOMERS'
    )
)
UNION ALL
SELECT
    ref_entity_name, SPLIT_PART(ref_entity_name, '.', 2), SPLIT_PART(ref_entity_name, '.', 3),
    metric_name, schedule, schedule_status
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE', REF_ENTITY_NAME => 'CORE.TRANSACTIONS'
    )
)
UNION ALL
SELECT
    ref_entity_name, SPLIT_PART(ref_entity_name, '.', 2), SPLIT_PART(ref_entity_name, '.', 3),
    metric_name, schedule, schedule_status
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE', REF_ENTITY_NAME => 'CORE.TICKETS'
    )
);

GRANT SELECT ON VIEW GOVERNANCE.V_DMF_REGISTRATIONS TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON VIEW GOVERNANCE.V_DMF_REGISTRATIONS TO APPLICATION ROLE NEXUS_ADMIN;

-- Stub sempre válido (zero linhas) — em contas Enterprise Edition, substituir por
-- SELECT a partir de SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS para ver
-- resultados reais de medição em vez de apenas a configuração registrada acima.
CREATE OR REPLACE VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD AS
SELECT
    CURRENT_TIMESTAMP()::TIMESTAMP_TZ AS measurement_time,
    ''::VARCHAR                       AS table_schema,
    ''::VARCHAR                       AS table_name,
    ''::VARCHAR                       AS metric_name,
    0::NUMBER                         AS value,
    'OK'::VARCHAR                     AS quality_status
WHERE FALSE;

GRANT SELECT ON VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT ON VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD TO APPLICATION ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Masking Policies (PII) — NEXUS_ADMIN vê dados reais; demais application roles
-- recebem valores mascarados. IS_APPLICATION_ROLE_IN_SESSION é o builtin correto
-- para checar application roles do consumer a partir de código dentro do próprio
-- Native App (CURRENT_ROLE() retornaria a role da conta do consumer, não a app role).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE MASKING POLICY IF NOT EXISTS GOVERNANCE.MASK_EMAIL
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_APPLICATION_ROLE_IN_SESSION('NEXUS_ADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE REGEXP_REPLACE(val, '(^[^@]{1,2})[^@]*(@.*)', '\\1***\\2')
    END
COMMENT = 'Mascara email: j***@example.com para non-admin';

CREATE MASKING POLICY IF NOT EXISTS GOVERNANCE.MASK_PHONE
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_APPLICATION_ROLE_IN_SESSION('NEXUS_ADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE REGEXP_REPLACE(val, '(\\d{2})(\\d+)(\\d{2})', '\\1****\\3')
    END
COMMENT = 'Mascara telefone: mantém primeiros e últimos 2 dígitos';

CREATE MASKING POLICY IF NOT EXISTS GOVERNANCE.MASK_NAME
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_APPLICATION_ROLE_IN_SESSION('NEXUS_ADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE SPLIT_PART(val, ' ', 1) || ' ****'
    END
COMMENT = 'Mascara sobrenome: mantém apenas primeiro nome';

CREATE MASKING POLICY IF NOT EXISTS GOVERNANCE.MASK_TEXT_PII
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_APPLICATION_ROLE_IN_SESSION('NEXUS_ADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '[CONTEÚDO MASCARADO — APENAS NEXUS_ADMIN]'
    END
COMMENT = 'Mascara campos de texto com possível PII (prompts, descrições)';

ALTER TABLE CORE.CUSTOMERS MODIFY COLUMN email SET MASKING POLICY GOVERNANCE.MASK_EMAIL FORCE;
ALTER TABLE CORE.CUSTOMERS MODIFY COLUMN phone SET MASKING POLICY GOVERNANCE.MASK_PHONE FORCE;
ALTER TABLE CORE.CUSTOMERS MODIFY COLUMN name  SET MASKING POLICY GOVERNANCE.MASK_NAME  FORCE;

ALTER TABLE AUDIT.PROMPT_LOG MODIFY COLUMN user_name   SET MASKING POLICY GOVERNANCE.MASK_NAME     FORCE;
ALTER TABLE AUDIT.PROMPT_LOG MODIFY COLUMN prompt_text SET MASKING POLICY GOVERNANCE.MASK_TEXT_PII FORCE;
-- NOTA: CORE.INTERACTIONS ainda não existe neste ponto do script (criada na seção
-- "Tabelas canônicas ausentes" mais abaixo) — a máscara de body é aplicada lá.

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P0: External Access Integration (APIs externas via Native App)
--
-- REMOVIDO do setup script: "External access is not supported for trial
-- accounts" é um erro de compilação da própria conta, levantado na fase de
-- VALIDAÇÃO do setup script (antes de qualquer statement realmente executar)
-- — não é um erro de runtime, então EXECUTE IMMEDIATE ... EXCEPTION WHEN
-- OTHER não o captura (tentado e confirmado; a instalação inteira falhava
-- mesmo com o bloco de tratamento de erro). NEXUS_API_EAI não é referenciada
-- em nenhum outro lugar deste arquivo. Reintroduzir exige um mecanismo que
-- verifique a edition/capacidade da conta ANTES de declarar o EAI no script
-- (ex.: gerar o setup_script.sql condicionalmente no pipeline de release, já
-- que não há como fazer isso dentro do próprio SQL).
-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P0: Stored Procedures para as Tasks de refresh automático
-- churn_model.py e recommendation_model.py chegam ao consumer como parte do
-- pacote do Native App (ver snowflake.yml artifacts: snowflake/models/ → ./models/
-- e .github/workflows/04-release-native-app.yml, que faz PUT dos mesmos arquivos
-- em {STAGE}/models/). Por isso o IMPORTS abaixo é um caminho relativo ao pacote,
-- não um stage de runtime — CORE.ML_STAGE é para upload futuro de modelos custom.
-- ─────────────────────────────────────────────────────────────────────────────

-- NOTA: código inline (não IMPORTS) porque CORE é um schema não-versionado —
-- Native Apps só permitem IMPORTS de arquivos staged em "versioned schemas"
-- (erro observado: "Procedure ... created in non-versioned schema is not
-- allowed to have imports (inline only)"). PACKAGES continua funcionando
-- normalmente (não é IMPORTS); só staged files (models/*.py) são proibidos.
-- Espelha snowflake/models/churn_model.py + recommendation_model.py.
CREATE OR REPLACE PROCEDURE CORE.SP_RUN_CHURN_PIPELINE(MODE VARCHAR DEFAULT 'full')
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
HANDLER = 'run_churn_pipeline'
AS
$$
import json

from snowflake.ml.modeling.linear_model import LogisticRegression
from snowflake.ml.modeling.pipeline import Pipeline
from snowflake.ml.modeling.preprocessing import StandardScaler
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lit, when

MODEL_VERSION = "1.0.0-lr"

FEATURE_COLS = [
    "HEALTH_SCORE",
    "NPS_SCORE",
    "CHURN_PROBABILITY",
    "EVENTS_30D",
    "ACTIVE_DAYS_30D",
    "DAYS_SINCE_LAST_ACTIVITY",
    "OPEN_TICKETS",
    "SLA_BREACHES",
    "MRR",
]

LABEL_COL   = "IS_CHURNED"
PREDICT_COL = "ML_CHURN_PROBABILITY"


def _risk_level(prob):
    if prob >= 0.65:
        return "HIGH"
    elif prob >= 0.35:
        return "MEDIUM"
    return "LOW"


def _top_drivers(row):
    drivers = []
    if row.get("HEALTH_SCORE", 100) < 40:
        drivers.append("health_score_crítico")
    if row.get("NPS_SCORE", 0) < -20:
        drivers.append("nps_muito_baixo")
    if row.get("ACTIVE_DAYS_30D", 30) < 5:
        drivers.append("baixo_engajamento")
    if row.get("DAYS_SINCE_LAST_ACTIVITY", 0) > 14:
        drivers.append("inatividade_prolongada")
    if row.get("SLA_BREACHES", 0) > 2:
        drivers.append("multiplas_violacoes_sla")
    if row.get("OPEN_TICKETS", 0) > 3:
        drivers.append("acumulo_de_tickets")
    if row.get("MRR", 1) < 100:
        drivers.append("baixo_mrr")
    return drivers[:3] if drivers else ["perfil_de_risco_moderado"]


def _recommended_action(risk, drivers):
    if risk == "HIGH":
        if "baixo_engajamento" in drivers or "inatividade_prolongada" in drivers:
            return "Agendar QBR urgente e oferecer onboarding adicional"
        if "multiplas_violacoes_sla" in drivers:
            return "Escalar para time de CS sênior e revisar SLA"
        return "Contato imediato do CSM + oferta de desconto de retenção"
    elif risk == "MEDIUM":
        if "nps_muito_baixo" in drivers:
            return "Realizar NPS follow-up e coletar feedback detalhado"
        return "Aumentar cadência de contato e revisar health score mensalmente"
    return "Manter cadência padrão e monitorar próxima renovação"


def train_and_score(session):
    df = session.table("MART.CUSTOMER_360")
    df = df.with_column(
        LABEL_COL,
        when(col("LIFECYCLE_STAGE") == lit("churned"), lit(1.0)).otherwise(lit(0.0))
    )
    for f in FEATURE_COLS:
        df = df.fill_na({f: 0.0})

    pipeline = Pipeline(
        steps=[
            ("scaler", StandardScaler(input_cols=FEATURE_COLS, output_cols=FEATURE_COLS)),
            ("model",  LogisticRegression(
                input_cols=FEATURE_COLS,
                label_cols=[LABEL_COL],
                output_cols=[PREDICT_COL],
                max_iter=200,
                C=0.5,
            )),
        ]
    )

    train_df = df.filter(col("LIFECYCLE_STAGE").isin(["churned", "active", "at_risk"]))
    pipeline.fit(train_df)

    active_df = df.filter(col("LIFECYCLE_STAGE") != lit("churned"))
    scored_df = pipeline.predict(active_df)

    rows = scored_df.select(
        "CUSTOMER_ID", "ORG_ID",
        PREDICT_COL,
        "HEALTH_SCORE", "NPS_SCORE", "ACTIVE_DAYS_30D",
        "DAYS_SINCE_LAST_ACTIVITY", "SLA_BREACHES", "OPEN_TICKETS", "MRR",
    ).collect()

    if not rows:
        return "ERROR: nenhum cliente ativo para pontuar"

    inserted = 0
    for r in rows:
        prob     = max(0.0, min(1.0, float(r[PREDICT_COL])))
        risk     = _risk_level(prob)
        row_dict = {c: r[c] for c in [
            "HEALTH_SCORE", "NPS_SCORE", "ACTIVE_DAYS_30D",
            "DAYS_SINCE_LAST_ACTIVITY", "SLA_BREACHES", "OPEN_TICKETS", "MRR",
        ]}
        drivers  = _top_drivers(row_dict)
        action   = _recommended_action(risk, drivers)
        arr_risk = float(r["MRR"] or 0) * 12 * prob

        drivers_json = json.dumps(drivers).replace("'", "''")
        action_esc   = action.replace("'", "''")
        customer_id  = r["CUSTOMER_ID"]
        org_id       = r["ORG_ID"]

        session.sql(f"""
            MERGE INTO AI.CHURN_SCORES tgt
            USING (
                SELECT '{customer_id}' AS customer_id, '{org_id}' AS org_id
            ) src ON (tgt.customer_id = src.customer_id AND tgt.org_id = src.org_id)
            WHEN MATCHED THEN UPDATE SET
                churn_probability        = {prob:.4f},
                risk_level               = '{risk}',
                top_drivers              = PARSE_JSON('{drivers_json}'),
                recommended_action       = '{action_esc}',
                expected_revenue_at_risk = {arr_risk:.2f},
                model_version            = '{MODEL_VERSION}',
                scored_at                = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT
                (org_id, customer_id, churn_probability, risk_level,
                 top_drivers, recommended_action, expected_revenue_at_risk, model_version)
            VALUES
                ('{org_id}', '{customer_id}', {prob:.4f}, '{risk}',
                 PARSE_JSON('{drivers_json}'), '{action_esc}', {arr_risk:.2f}, '{MODEL_VERSION}')
        """).collect()
        inserted += 1

    return f"OK: {inserted} clientes pontuados — modelo {MODEL_VERSION}"


def generate_recommendations(session, org_id="ORG-DEMO-001"):
    rows = session.sql(f"""
        SELECT
            cs.customer_id,
            cs.org_id,
            c.name                   AS customer_name,
            cs.risk_level,
            cs.churn_probability,
            cs.recommended_action,
            cs.top_drivers,
            cs.expected_revenue_at_risk,
            c360.health_score,
            c360.nps_score,
            c360.arr,
            c360.segment,
            c360.nearest_renewal_date
        FROM AI.CHURN_SCORES cs
        JOIN CORE.CUSTOMERS c
            ON cs.customer_id = c.customer_id AND cs.org_id = c.org_id
        JOIN MART.CUSTOMER_360 c360
            ON cs.customer_id = c360.customer_id
        LEFT JOIN AI.RECOMMENDATIONS r
            ON cs.customer_id = r.entity_id
           AND r.status = 'pending'
           AND r.is_active = TRUE
           AND r.recommendation_type = 'churn_prevention'
           AND r.created_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
        WHERE cs.org_id = '{org_id}'
          AND cs.risk_level IN ('HIGH', 'MEDIUM')
          AND r.recommendation_id IS NULL
        ORDER BY cs.expected_revenue_at_risk DESC
        LIMIT 20
    """).collect()

    if not rows:
        return "OK: sem novos clientes para gerar recomendações"

    generated = 0
    for r in rows:
        drivers_raw = r["TOP_DRIVERS"]
        try:
            drivers_str = ", ".join(
                json.loads(drivers_raw) if isinstance(drivers_raw, str) else drivers_raw
            )
        except Exception:
            drivers_str = str(drivers_raw)

        prompt = (
            f"Você é um Customer Success Manager sênior. "
            f"Gere UMA recomendação de ação clara e objetiva (máximo 2 frases) para prevenir o churn "
            f"de {r['CUSTOMER_NAME']} ({r['SEGMENT']}). "
            f"ARR: US$ {r['ARR']:,.0f}. "
            f"Risk: {r['RISK_LEVEL']} ({r['CHURN_PROBABILITY']:.0%}). "
            f"Drivers: {drivers_str}. "
            f"Health Score: {r['HEALTH_SCORE']}. "
            f"NPS: {r['NPS_SCORE']}. "
            f"Renovação: {r['NEAREST_RENEWAL_DATE']}. "
            f"Responda em português, sem bullet points, focado em ação imediata."
        ).replace("'", "''")

        rec_row = session.sql(
            f"SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', '{prompt}') AS rec"
        ).collect()
        rec_text = (rec_row[0]["REC"] or r["RECOMMENDED_ACTION"]).strip()

        priority   = "HIGH" if r["RISK_LEVEL"] == "HIGH" else "MEDIUM"
        impact_usd = float(r["EXPECTED_REVENUE_AT_RISK"] or 0)
        rec_esc    = rec_text.replace("'", "''")
        cid        = r["CUSTOMER_ID"]
        oid        = r["ORG_ID"]

        session.sql(f"""
            INSERT INTO AI.RECOMMENDATIONS
                (org_id, entity_id, entity_type, recommendation_type,
                 priority, recommendation_text, expected_impact_usd,
                 confidence_score, owner_role, status)
            VALUES
                ('{oid}', '{cid}', 'customer', 'churn_prevention',
                 '{priority}', '{rec_esc}', {impact_usd:.2f},
                 {r['CHURN_PROBABILITY']:.4f}, 'customer_success', 'pending')
        """).collect()
        generated += 1

    return f"OK: {generated} recomendações geradas"


def run_all_orgs(session):
    orgs = session.sql(
        "SELECT DISTINCT org_id FROM CORE.CUSTOMERS WHERE lifecycle_stage != 'churned'"
    ).collect()
    results = [generate_recommendations(session, r["ORG_ID"]) for r in orgs]
    return " | ".join(results) if results else "OK: nenhum org ativo"


def run_churn_pipeline(session, mode="full"):
    results = []
    if mode in ("score", "full"):
        results.append(train_and_score(session))
    if mode in ("recs", "full"):
        results.append(run_all_orgs(session))
    return " | ".join(results)
$$;

GRANT USAGE ON PROCEDURE CORE.SP_RUN_CHURN_PIPELINE(VARCHAR) TO APPLICATION ROLE NEXUS_ADMIN;

CREATE TABLE IF NOT EXISTS AI.EXECUTIVE_BRIEFINGS (
    briefing_id     VARCHAR(36)    DEFAULT UUID_STRING(),
    org_id          VARCHAR(100)   NOT NULL,
    briefing_date   DATE           DEFAULT CURRENT_DATE(),
    briefing_type   VARCHAR(50)    DEFAULT 'DAILY',
    content         TEXT,
    kpi_snapshot    VARIANT,
    model_used      VARCHAR(100)   DEFAULT 'claude-3-5-sonnet',
    tokens_used     INTEGER,
    latency_ms      INTEGER,
    created_at      TIMESTAMP_TZ   DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_executive_briefings PRIMARY KEY (briefing_id)
);

EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.EXECUTIVE_BRIEFINGS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

CREATE OR REPLACE VIEW AI.V_LATEST_EXECUTIVE_BRIEFING AS
SELECT
    b.briefing_id, b.org_id, b.briefing_date, b.briefing_type,
    b.content, b.kpi_snapshot, b.model_used, b.latency_ms, b.created_at
FROM AI.EXECUTIVE_BRIEFINGS b
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY b.org_id, b.briefing_type ORDER BY b.created_at DESC
) = 1;

GRANT SELECT ON TABLE AI.EXECUTIVE_BRIEFINGS         TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON VIEW  AI.V_LATEST_EXECUTIVE_BRIEFING TO APPLICATION ROLE NEXUS_VIEWER;

CREATE OR REPLACE PROCEDURE CORE.SP_GENERATE_EXECUTIVE_BRIEFING()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
import json
import time

def run(session):
    orgs = session.sql("""
        SELECT DISTINCT org_id
        FROM CORE.CUSTOMERS
        WHERE lifecycle_stage != 'churned'
          AND updated_at >= CURRENT_DATE() - 90
    """).collect()

    if not orgs:
        return "NO_ACTIVE_ORGS"

    results = []
    model = "claude-3-5-sonnet"

    for org_row in orgs:
        org_id = org_row["ORG_ID"]

        kpi_rows = session.sql("""
            SELECT
                COUNT(*)                                                AS total_customers,
                SUM(CASE WHEN churn_risk_level = 'HIGH'   THEN 1 ELSE 0 END) AS high_risk,
                SUM(CASE WHEN churn_risk_level = 'MEDIUM' THEN 1 ELSE 0 END) AS medium_risk,
                ROUND(SUM(arr), 2)                                      AS total_arr,
                ROUND(SUM(CASE WHEN churn_risk_level = 'HIGH' THEN arr ELSE 0 END), 2) AS arr_at_risk,
                ROUND(AVG(health_score), 1)                             AS avg_health_score,
                ROUND(AVG(nps_score), 1)                                AS avg_nps
            FROM MART.CUSTOMER_360
            WHERE org_id = ?
        """, params=[org_id]).collect()

        if not kpi_rows:
            continue

        k = kpi_rows[0].as_dict()

        delta_rows = session.sql("""
            SELECT
                SUM(CASE WHEN customer_since >= CURRENT_DATE() - 30 THEN 1 ELSE 0 END) AS new_30d,
                SUM(CASE WHEN lifecycle_stage = 'churned'
                          AND updated_at >= CURRENT_DATE() - 30 THEN 1 ELSE 0 END) AS churned_30d
            FROM CORE.CUSTOMERS
            WHERE org_id = ?
        """, params=[org_id]).collect()

        delta = delta_rows[0].as_dict() if delta_rows else {}

        kpi_snapshot = {**k, **delta}
        kpi_str = json.dumps(kpi_snapshot, default=str)

        prompt = (
            "Você é o Executive AI Briefing Agent do NEXUS AI DataOps. "
            "Com base nos KPIs abaixo, gere um briefing executivo conciso (máx 300 palavras) "
            "em português com as seções: "
            "(1) Resumo do dia, "
            "(2) Top 3 riscos imediatos, "
            "(3) Top 3 oportunidades de receita, "
            "(4) Ações recomendadas para as próximas 24h. "
            f"KPIs: {kpi_str}"
        )

        t0 = time.time()
        briefing_rows = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(?, ?) AS briefing_text",
            params=[model, prompt]
        ).collect()
        latency_ms = int((time.time() - t0) * 1000)

        briefing_text = briefing_rows[0]["BRIEFING_TEXT"] if briefing_rows else ""

        if not briefing_text:
            results.append(f"{org_id}:EMPTY_RESPONSE")
            continue

        session.sql("""
            INSERT INTO AI.EXECUTIVE_BRIEFINGS
                (org_id, briefing_date, briefing_type, content, kpi_snapshot,
                 model_used, tokens_used, latency_ms)
            VALUES (?, CURRENT_DATE(), 'DAILY', ?, PARSE_JSON(?), ?, 0, ?)
        """, params=[org_id, briefing_text, kpi_str, model, latency_ms]).collect()

        session.sql("""
            MERGE INTO AI.RECOMMENDATIONS AS tgt
            USING (
                SELECT
                    ?                                       AS org_id,
                    'executive'                             AS entity_id,
                    'briefing'                               AS entity_type,
                    'daily_briefing'                         AS recommendation_type,
                    'HIGH'                                    AS priority,
                    ?                                          AS recommendation_text,
                    CURRENT_TIMESTAMP() + INTERVAL '1 day'   AS expires_at
            ) AS src
            ON  tgt.org_id               = src.org_id
            AND tgt.entity_id            = src.entity_id
            AND tgt.recommendation_type  = src.recommendation_type
            AND tgt.expires_at           > CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (
                org_id, entity_id, entity_type, recommendation_type,
                priority, recommendation_text, expires_at
            ) VALUES (
                src.org_id, src.entity_id, src.entity_type, src.recommendation_type,
                src.priority, src.recommendation_text, src.expires_at
            )
        """, params=[org_id, briefing_text[:1000]]).collect()

        results.append(f"{org_id}:OK")

    return "BRIEFINGS_GENERATED:" + ",".join(results)
$$;

GRANT USAGE ON PROCEDURE CORE.SP_GENERATE_EXECUTIVE_BRIEFING() TO APPLICATION ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P0: Tasks de ingestão e refresh automático
-- ─────────────────────────────────────────────────────────────────────────────

-- Task: atualizar churn scores via Snowpark ML (corrige AT-010)
CREATE OR REPLACE TASK CORE.TASK_RUN_CHURN_PIPELINE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'
    COMMENT   = 'Executa pipeline de churn diariamente às 2h UTC'
AS
    CALL CORE.SP_RUN_CHURN_PIPELINE('full');

-- Task: gerar briefing executivo diário (corrige AT-010)
CREATE OR REPLACE TASK CORE.TASK_EXECUTIVE_BRIEFING
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 7 * * * UTC'
    COMMENT   = 'Gera briefing executivo de IA todo dia às 7h UTC'
AS
    CALL CORE.SP_GENERATE_EXECUTIVE_BRIEFING();

-- Task: refresh do Revenue Opportunity Score
CREATE OR REPLACE TASK MART.TASK_REFRESH_REVENUE_SCORE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 */6 * * * UTC'
    COMMENT   = 'Atualiza Revenue Opportunity Score a cada 6h'
AS
    INSERT INTO MART.REVENUE_OPPORTUNITY_SCORE (
        customer_id, org_id, customer_name, opportunity_score, opportunity_type,
        estimated_revenue_usd, confidence, churn_risk, contract_end_date, arr, scored_at
    )
    WITH latest_churn AS (
        SELECT customer_id, org_id, churn_probability
        FROM AI.CHURN_SCORES
        QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id, org_id ORDER BY scored_at DESC) = 1
    )
    SELECT
        c.customer_id,
        c.org_id,
        c.name                                                  AS customer_name,
        CASE
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.3 AND c.arr > 50000 THEN 0.85
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.3 AND c.arr > 20000 THEN 0.70
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.5 THEN 0.55
            ELSE 0.20
        END                                                     AS opportunity_score,
        CASE
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.3 THEN 'upsell'
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.5 THEN 'expansion'
            ELSE 'retention'
        END                                                     AS opportunity_type,
        c.arr * CASE
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.3 THEN 0.25
            WHEN COALESCE(churn.churn_probability, 0.5) < 0.5 THEN 0.10
            ELSE 0.05
        END                                                     AS estimated_revenue_usd,
        1 - COALESCE(churn.churn_probability, 0.5)              AS confidence,
        COALESCE(churn.churn_probability, 0.5)                  AS churn_risk,
        c.contract_end_date,
        c.arr,
        CURRENT_TIMESTAMP()
    FROM CORE.CUSTOMERS c
    LEFT JOIN latest_churn churn
        ON c.customer_id = churn.customer_id AND c.org_id = churn.org_id
    WHERE NOT EXISTS (
        SELECT 1 FROM MART.REVENUE_OPPORTUNITY_SCORE r
        WHERE r.customer_id = c.customer_id
          AND r.scored_at   > DATEADD('hour', -6, CURRENT_TIMESTAMP())
    );

-- Tolerante: EXECUTE TASK só pode ser concedido à application depois que a
-- versão atual (que declara o privilégio no manifest.yml) já estiver
-- instalada — na 1a instalação/upgrade que introduz o privilégio, o consumer
-- ainda não teve chance de concedê-lo. RESUME falharia com "EXECUTE TASK
-- privilege must be granted to owner role" e derrubaria a instalação
-- inteira. Uma vez concedido (ver step de CI), upgrades seguintes resumem
-- normalmente.
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TASK CORE.TASK_RUN_CHURN_PIPELINE    RESUME;
    ALTER TASK CORE.TASK_EXECUTIVE_BRIEFING    RESUME;
    ALTER TASK MART.TASK_REFRESH_REVENUE_SCORE RESUME;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P1: Tabelas canônicas ausentes (CONTEXT.md seção 34)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CORE.ACCOUNTS (
    account_id      VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(50)   NOT NULL,
    customer_id     VARCHAR(36),
    account_name    VARCHAR(255)  NOT NULL,
    account_type    VARCHAR(50),
    industry        VARCHAR(100),
    employee_count  INTEGER,
    annual_revenue  DECIMAL(18,2),
    website         VARCHAR(500),
    created_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (account_id)
);

CREATE TABLE IF NOT EXISTS CORE.PRODUCTS (
    product_id       VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id           VARCHAR(50)   NOT NULL,
    product_name     VARCHAR(255)  NOT NULL,
    product_category VARCHAR(100),
    description      TEXT,
    unit_price       DECIMAL(18,2),
    currency         VARCHAR(10)   DEFAULT 'USD',
    is_active        BOOLEAN       DEFAULT TRUE,
    created_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (product_id)
);

CREATE TABLE IF NOT EXISTS CORE.INTERACTIONS (
    interaction_id   VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id           VARCHAR(50)   NOT NULL,
    customer_id      VARCHAR(36),
    channel          VARCHAR(50),
    direction        VARCHAR(10),
    subject          VARCHAR(500),
    body             TEXT,
    sentiment_score  DECIMAL(4,2),
    outcome          VARCHAR(100),
    occurred_at      TIMESTAMP_TZ  NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    created_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (interaction_id)
);

-- Aplicar RAP nas novas tabelas canônicas
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.ACCOUNTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.PRODUCTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE CORE.INTERACTIONS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
ALTER TABLE CORE.INTERACTIONS MODIFY COLUMN body SET MASKING POLICY GOVERNANCE.MASK_TEXT_PII FORCE;

-- Revenue Opportunity Score — tabela target das Tasks
-- customer_name/churn_risk/contract_end_date/arr são denormalizados aqui (em vez de
-- exigir JOIN em runtime) porque revenue_opportunity_model.yaml (Cortex Analyst)
-- os expõe como dimensions/measures diretas desta tabela.
CREATE TABLE IF NOT EXISTS MART.REVENUE_OPPORTUNITY_SCORE (
    score_id             VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    customer_id          VARCHAR(36)   NOT NULL,
    org_id               VARCHAR(50)   NOT NULL,
    customer_name        VARCHAR(500),
    opportunity_score    DECIMAL(4,2),
    opportunity_type     VARCHAR(50),
    estimated_revenue_usd DECIMAL(18,2),
    confidence           DECIMAL(4,2),
    churn_risk           DECIMAL(5,4),
    contract_end_date    DATE,
    arr                  DECIMAL(18,2),
    scored_at            TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (score_id)
);

-- Migrations: garante colunas adicionadas após versões anteriores
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE ADD COLUMN IF NOT EXISTS customer_name     VARCHAR(500);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE ADD COLUMN IF NOT EXISTS churn_risk        DECIMAL(5,4);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE ADD COLUMN IF NOT EXISTS contract_end_date DATE;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;
EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE ADD COLUMN IF NOT EXISTS arr               DECIMAL(18,2);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

ALTER TABLE MART.REVENUE_OPPORTUNITY_SCORE
    ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P1: Dynamic Tables no setup_script (chegam ao consumer via Native App)
-- NOTA: DT_EXECUTIVE_KPIS e DT_CUSTOMER_HEALTH já foram declaradas acima
-- (canônicas, usadas por Home.py / 1_Executive_Command.py / 12_Operations_Intelligence.py
-- / operations_model.yaml). As definições duplicadas que existiam aqui referenciavam
-- CORE.CUSTOMERS.churn_risk_score, coluna inexistente, e quebravam o setup_script —
-- foram removidas em vez de recriadas com CREATE OR REPLACE. DT_REVENUE_MOVEMENT foi
-- movida para perto das outras Dynamic Tables (ver acima) porque os GRANTs na seção
-- "Grants para Application Roles" a referenciavam antes dela existir.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P1: Agent-specific roles (RBAC granular por agente)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE APPLICATION ROLE IF NOT EXISTS AGENT_EXECUTIVE_READONLY;
CREATE APPLICATION ROLE IF NOT EXISTS AGENT_REVENUE_READONLY;
CREATE APPLICATION ROLE IF NOT EXISTS AGENT_CUSTOMER_READONLY;
CREATE APPLICATION ROLE IF NOT EXISTS AGENT_RISK_READONLY;
CREATE APPLICATION ROLE IF NOT EXISTS AGENT_OPS_READONLY;

GRANT APPLICATION ROLE AGENT_EXECUTIVE_READONLY TO APPLICATION ROLE NEXUS_VIEWER;
GRANT APPLICATION ROLE AGENT_REVENUE_READONLY   TO APPLICATION ROLE NEXUS_ANALYST;
GRANT APPLICATION ROLE AGENT_CUSTOMER_READONLY  TO APPLICATION ROLE NEXUS_ANALYST;
GRANT APPLICATION ROLE AGENT_RISK_READONLY      TO APPLICATION ROLE NEXUS_ANALYST;
GRANT APPLICATION ROLE AGENT_OPS_READONLY       TO APPLICATION ROLE NEXUS_ANALYST;

GRANT SELECT ON DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS   TO APPLICATION ROLE AGENT_EXECUTIVE_READONLY;
GRANT SELECT ON DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH  TO APPLICATION ROLE AGENT_CUSTOMER_READONLY;
GRANT SELECT ON DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT TO APPLICATION ROLE AGENT_REVENUE_READONLY;
GRANT SELECT ON TABLE CORE.TICKETS                     TO APPLICATION ROLE AGENT_OPS_READONLY;
GRANT SELECT ON TABLE CORE.INTERACTIONS                TO APPLICATION ROLE AGENT_OPS_READONLY;

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 2 — P1: KBS (Knowledge Base Systems) — CONTEXT.md seção 36
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS KBS;

CREATE TABLE IF NOT EXISTS KBS.DOCUMENTS (
    doc_id        VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    kb_name       VARCHAR(100)  NOT NULL,
    title         VARCHAR(500)  NOT NULL,
    content       TEXT          NOT NULL,
    source_url    VARCHAR(1000),
    doc_type      VARCHAR(50),
    version       VARCHAR(20),
    chunk_index   INTEGER       DEFAULT 0,
    total_chunks  INTEGER       DEFAULT 1,
    indexed_at    TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    is_active     BOOLEAN       DEFAULT TRUE,
    PRIMARY KEY   (doc_id)
);

ALTER TABLE KBS.DOCUMENTS CLUSTER BY (kb_name);

CREATE TABLE IF NOT EXISTS KBS.SOURCES (
    source_id    VARCHAR(36)    NOT NULL DEFAULT UUID_STRING(),
    kb_name      VARCHAR(100)   NOT NULL,
    source_url   VARCHAR(1000)  NOT NULL,
    title        VARCHAR(500),
    last_crawled TIMESTAMP_TZ,
    doc_count    INTEGER        DEFAULT 0,
    is_active    BOOLEAN        DEFAULT TRUE,
    PRIMARY KEY  (source_id)
);

CREATE TABLE IF NOT EXISTS KBS.SEARCH_LOGS (
    log_id        VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    kb_name       VARCHAR(100),
    query_text    TEXT,
    result_count  INTEGER,
    top_doc_id    VARCHAR(36),
    user_feedback VARCHAR(20),
    latency_ms    INTEGER,
    created_at    TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY   (log_id)
);

-- Seed: fontes das 2 KBs prioritárias (indexação via pipeline externo)
MERGE INTO KBS.SOURCES t
USING (
    SELECT 'KB_SNOWFLAKE_CORE' AS kb_name, 'https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-about' AS source_url, 'Native App Framework'    AS title UNION ALL
    SELECT 'KB_SNOWFLAKE_CORE', 'https://docs.snowflake.com/en/user-guide/dynamic-tables-intro',                         'Dynamic Tables Overview' UNION ALL
    SELECT 'KB_SNOWFLAKE_CORE', 'https://docs.snowflake.com/en/user-guide/tasks-intro',                                  'Tasks Introduction'      UNION ALL
    SELECT 'KB_SNOWFLAKE_CORE', 'https://docs.snowflake.com/en/user-guide/streams-intro',                                'Streams Introduction'    UNION ALL
    SELECT 'KB_CORTEX_AI',      'https://docs.snowflake.com/en/user-guide/cortex-search/cortex-search-overview',         'Cortex Search Overview'  UNION ALL
    SELECT 'KB_CORTEX_AI',      'https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst',              'Cortex Analyst'          UNION ALL
    SELECT 'KB_CORTEX_AI',      'https://docs.snowflake.com/en/user-guide/cortex-agents',                                'Cortex Agents'
) s ON t.kb_name = s.kb_name AND t.source_url = s.source_url
WHEN NOT MATCHED THEN INSERT (kb_name, source_url, title) VALUES (s.kb_name, s.source_url, s.title);

-- Cortex Search Service unificado para todas as KBs (filtro por kb_name em queries)
EXECUTE IMMEDIATE $$
BEGIN
    CREATE OR REPLACE CORTEX SEARCH SERVICE KBS.KB_SEARCH_SERVICE
        ON content
        ATTRIBUTES kb_name, doc_type, source_url, title
        WAREHOUSE  = NEXUS_COMPUTE_WH
        TARGET_LAG = '7 days'
    AS (
        SELECT content, kb_name, doc_type, source_url, title, doc_id
        FROM KBS.DOCUMENTS
        WHERE is_active = TRUE
    );
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

GRANT USAGE ON SCHEMA KBS TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON ALL TABLES IN SCHEMA KBS TO APPLICATION ROLE NEXUS_ANALYST;

-- ─────────────────────────────────────────────────────────────────────────────
-- Demo data — seed idempotente para demonstração do Native App
-- ─────────────────────────────────────────────────────────────────────────────

MERGE INTO CORE.CUSTOMERS tgt
USING (
    SELECT 'CUST-DEMO-001' AS customer_id, 'ORG-DEMO-001' AS org_id, 'Acme Corp'       AS name, 'admin@acme.com'     AS email, 'Enterprise'  AS segment, 'LATAM' AS region, 'Technology' AS industry, 'active'  AS lifecycle_stage, 120000.00 AS arr, 10000.00 AS mrr, 45  AS nps_score, '2026-12-31'::DATE AS contract_end_date UNION ALL
    SELECT 'CUST-DEMO-002', 'ORG-DEMO-001', 'Beta Saúde',      'admin@beta.com',    'Enterprise',  'LATAM', 'Healthcare',  'at_risk', 95000.00,  7916.00,  18,  '2026-09-30'::DATE UNION ALL
    SELECT 'CUST-DEMO-003', 'ORG-DEMO-001', 'Gama Retail',     'admin@gama.com',    'Mid-Market',  'LATAM', 'Retail',      'active',  48000.00,  4000.00,  52,  '2027-03-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-004', 'ORG-DEMO-001', 'Delta Fintech',   'admin@delta.com',   'Enterprise',  'USA',   'Financial',   'at_risk', 200000.00, 16666.00, 12,  '2026-08-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-005', 'ORG-DEMO-001', 'Epsilon Tech',    'admin@epsilon.com', 'Mid-Market',  'USA',   'Technology',  'active',  36000.00,  3000.00,  38,  '2027-06-30'::DATE UNION ALL
    SELECT 'CUST-DEMO-006', 'ORG-DEMO-001', 'Zeta Logística',  'admin@zeta.com',    'SMB',         'LATAM', 'Logistics',   'active',  18000.00,  1500.00,  55,  '2027-01-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-007', 'ORG-DEMO-001', 'Eta Educação',    'admin@eta.com',     'Mid-Market',  'LATAM', 'Education',   'active',  42000.00,  3500.00,  60,  '2026-11-30'::DATE UNION ALL
    SELECT 'CUST-DEMO-008', 'ORG-DEMO-001', 'Theta Energia',   'admin@theta.com',   'Enterprise',  'LATAM', 'Energy',      'churned', 75000.00,  6250.00,  -10, '2026-03-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-009', 'ORG-DEMO-001', 'Iota Seguros',    'admin@iota.com',    'Mid-Market',  'USA',   'Insurance',   'active',  60000.00,  5000.00,  42,  '2027-02-28'::DATE UNION ALL
    SELECT 'CUST-DEMO-010', 'ORG-DEMO-001', 'Kappa Telecom',   'admin@kappa.com',   'Enterprise',  'LATAM', 'Telecom',     'active',  150000.00, 12500.00, 35,  '2026-10-31'::DATE
) src ON (tgt.customer_id = src.customer_id)
WHEN NOT MATCHED THEN INSERT
    (customer_id, org_id, name, email, segment, region, industry, lifecycle_stage, arr, mrr, nps_score, contract_end_date)
    VALUES (src.customer_id, src.org_id, src.name, src.email, src.segment, src.region, src.industry, src.lifecycle_stage, src.arr, src.mrr, src.nps_score, src.contract_end_date)
WHEN MATCHED THEN UPDATE SET
    name = src.name, lifecycle_stage = src.lifecycle_stage, arr = src.arr, mrr = src.mrr,
    nps_score = src.nps_score, contract_end_date = src.contract_end_date;

MERGE INTO CORE.SUBSCRIPTIONS tgt
USING (
    SELECT 'SUB-DEMO-001' AS subscription_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'Enterprise Suite' AS plan_name, 'enterprise' AS plan_tier, 'active' AS status, 10000.00 AS mrr, 120000.00 AS arr, '2026-12-31'::DATE AS renewal_date UNION ALL
    SELECT 'SUB-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 'Enterprise Suite',  'enterprise', 'active',  7916.00,  95000.00,  '2026-09-30'::DATE UNION ALL
    SELECT 'SUB-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 'Growth',            'standard',   'active',  4000.00,  48000.00,  '2027-03-31'::DATE UNION ALL
    SELECT 'SUB-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 'Enterprise Suite',  'enterprise', 'active',  16666.00, 200000.00, '2026-08-31'::DATE UNION ALL
    SELECT 'SUB-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 'Growth',            'standard',   'active',  3000.00,  36000.00,  '2027-06-30'::DATE UNION ALL
    SELECT 'SUB-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-006', 'Starter',           'basic',      'active',  1500.00,  18000.00,  '2027-01-31'::DATE UNION ALL
    SELECT 'SUB-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-007', 'Growth',            'standard',   'active',  3500.00,  42000.00,  '2026-11-30'::DATE UNION ALL
    SELECT 'SUB-DEMO-008', 'ORG-DEMO-001', 'CUST-DEMO-008', 'Enterprise Suite',  'enterprise', 'cancelled', 6250.00, 75000.00, '2026-03-31'::DATE UNION ALL
    SELECT 'SUB-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-009', 'Growth',            'standard',   'active',  5000.00,  60000.00,  '2027-02-28'::DATE UNION ALL
    SELECT 'SUB-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-010', 'Enterprise Suite',  'enterprise', 'active',  12500.00, 150000.00, '2026-10-31'::DATE
) src ON (tgt.subscription_id = src.subscription_id)
WHEN NOT MATCHED THEN INSERT
    (subscription_id, org_id, customer_id, plan_name, plan_tier, status, mrr, arr, renewal_date)
    VALUES (src.subscription_id, src.org_id, src.customer_id, src.plan_name, src.plan_tier, src.status, src.mrr, src.arr, src.renewal_date)
WHEN MATCHED THEN UPDATE SET status = src.status, mrr = src.mrr, arr = src.arr;

MERGE INTO CORE.CONTRACTS tgt
USING (
    SELECT 'CONT-DEMO-001' AS contract_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'Contrato Acme Corp 2026'      AS contract_name, 120000.00 AS contract_value, '2026-01-01'::DATE AS start_date, '2026-12-31'::DATE AS end_date, TRUE  AS auto_renewal, 'active' AS status UNION ALL
    SELECT 'CONT-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 'Contrato Beta Saúde 2026',      95000.00, '2025-10-01'::DATE, '2026-09-30'::DATE, FALSE, 'active'  UNION ALL
    SELECT 'CONT-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 'Contrato Gama Retail 2027',     48000.00, '2026-04-01'::DATE, '2027-03-31'::DATE, TRUE,  'active'  UNION ALL
    SELECT 'CONT-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 'Contrato Delta Fintech 2026',  200000.00, '2025-09-01'::DATE, '2026-08-31'::DATE, FALSE, 'active'  UNION ALL
    SELECT 'CONT-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 'Contrato Epsilon Tech 2027',    36000.00, '2026-07-01'::DATE, '2027-06-30'::DATE, TRUE,  'active'  UNION ALL
    SELECT 'CONT-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-006', 'Contrato Zeta Log. 2027',       18000.00, '2026-02-01'::DATE, '2027-01-31'::DATE, TRUE,  'active'  UNION ALL
    SELECT 'CONT-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-007', 'Contrato Eta Educação 2026',    42000.00, '2025-12-01'::DATE, '2026-11-30'::DATE, FALSE, 'active'  UNION ALL
    SELECT 'CONT-DEMO-008', 'ORG-DEMO-001', 'CUST-DEMO-008', 'Contrato Theta Energia 2026',   75000.00, '2025-04-01'::DATE, '2026-03-31'::DATE, FALSE, 'expired' UNION ALL
    SELECT 'CONT-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-009', 'Contrato Iota Seguros 2027',    60000.00, '2026-03-01'::DATE, '2027-02-28'::DATE, TRUE,  'active'  UNION ALL
    SELECT 'CONT-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-010', 'Contrato Kappa Telecom 2026',  150000.00, '2025-11-01'::DATE, '2026-10-31'::DATE, TRUE,  'active'
) src ON (tgt.contract_id = src.contract_id)
WHEN NOT MATCHED THEN INSERT
    (contract_id, org_id, customer_id, contract_name, contract_value, start_date, end_date, auto_renewal, status)
    VALUES (src.contract_id, src.org_id, src.customer_id, src.contract_name, src.contract_value, src.start_date, src.end_date, src.auto_renewal, src.status)
WHEN MATCHED THEN UPDATE SET status = src.status, contract_value = src.contract_value;

MERGE INTO CORE.TICKETS tgt
USING (
    SELECT 'TICK-DEMO-001' AS ticket_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-002' AS customer_id, 'Integração API falhando em produção'          AS subject, 'open'     AS status, 'urgent' AS priority, TRUE  AS sla_breach, -0.65 AS sentiment_score, 'negative' AS sentiment_label UNION ALL
    SELECT 'TICK-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-004', 'Dados de relatório desatualizados',          'open',     'high',   TRUE,  -0.50, 'negative' UNION ALL
    SELECT 'TICK-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-004', 'Dashboard não carrega para equipe de vendas', 'open',    'urgent', FALSE, -0.72, 'negative' UNION ALL
    SELECT 'TICK-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-001', 'Dúvida sobre exportação em CSV',             'resolved', 'low',    FALSE, 0.45,  'positive' UNION ALL
    SELECT 'TICK-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-003', 'Lentidão nas queries de relatório',          'open',     'medium', FALSE, -0.20, 'negative' UNION ALL
    SELECT 'TICK-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-005', 'Solicitação de novo recurso — filtro por data', 'open',  'low',    FALSE, 0.15,  'neutral'  UNION ALL
    SELECT 'TICK-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-007', 'Configuração de SSO com Okta',              'resolved', 'medium', FALSE, 0.30,  'neutral'  UNION ALL
    SELECT 'TICK-DEMO-008', 'ORG-DEMO-001', 'CUST-DEMO-009', 'Permissões de usuário incorretas',          'open',     'high',   FALSE, -0.35, 'negative' UNION ALL
    SELECT 'TICK-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-010', 'Erro ao importar arquivo de dados grande',  'open',     'medium', FALSE, -0.18, 'negative' UNION ALL
    SELECT 'TICK-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-006', 'Onboarding — dúvida sobre conectores',      'resolved', 'low',    FALSE, 0.55,  'positive'
) src ON (tgt.ticket_id = src.ticket_id)
WHEN NOT MATCHED THEN INSERT
    (ticket_id, org_id, customer_id, subject, status, priority, sla_breach, sentiment_score, sentiment_label)
    VALUES (src.ticket_id, src.org_id, src.customer_id, src.subject, src.status, src.priority, src.sla_breach, src.sentiment_score, src.sentiment_label)
WHEN MATCHED THEN UPDATE SET status = src.status, sla_breach = src.sla_breach;

MERGE INTO CORE.PRODUCT_EVENTS tgt
USING (
    SELECT 'EVT-DEMO-001' AS event_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'dashboard_view'     AS event_type, 'Executive Command' AS feature_name, DATEADD('day', -2,  CURRENT_TIMESTAMP()) AS occurred_at UNION ALL
    SELECT 'EVT-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-001', 'ai_chat',           'Cortex AI Chat',    DATEADD('day', -1,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-001', 'report_export',     'Reports',           DATEADD('day', -5,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-003', 'dashboard_view',    'Customer 360',      DATEADD('day', -3,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-003', 'filter_applied',    'Filters',           DATEADD('day', -4,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-005', 'dashboard_view',    'Executive Command', DATEADD('day', -1,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-005', 'agent_invocation',  'AI Chat',           DATEADD('day', -2,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-008', 'ORG-DEMO-001', 'CUST-DEMO-006', 'dashboard_view',    'Customer 360',      DATEADD('day', -6,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-007', 'report_export',     'Reports',           DATEADD('day', -2,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-007', 'agent_invocation',  'Cortex AI Chat',    DATEADD('day', -3,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-011', 'ORG-DEMO-001', 'CUST-DEMO-009', 'dashboard_view',    'Executive Command', DATEADD('day', -1,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-012', 'ORG-DEMO-001', 'CUST-DEMO-009', 'ai_chat',           'Cortex AI Chat',    DATEADD('day', -4,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-013', 'ORG-DEMO-001', 'CUST-DEMO-010', 'dashboard_view',    'Executive Command', DATEADD('day', -2,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-014', 'ORG-DEMO-001', 'CUST-DEMO-010', 'report_export',     'Reports',           DATEADD('day', -5,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-015', 'ORG-DEMO-001', 'CUST-DEMO-002', 'dashboard_view',    'Customer 360',      DATEADD('day', -10, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-016', 'ORG-DEMO-001', 'CUST-DEMO-004', 'dashboard_view',    'Executive Command', DATEADD('day', -15, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-017', 'ORG-DEMO-001', 'CUST-DEMO-001', 'dashboard_view',    'Document Intel.',   DATEADD('day', -7,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-018', 'ORG-DEMO-001', 'CUST-DEMO-003', 'agent_invocation',  'Cortex AI Chat',    DATEADD('day', -8,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-019', 'ORG-DEMO-001', 'CUST-DEMO-006', 'ai_chat',           'Cortex AI Chat',    DATEADD('day', -9,  CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'EVT-DEMO-020', 'ORG-DEMO-001', 'CUST-DEMO-010', 'agent_invocation',  'AI Chat',           DATEADD('day', -3,  CURRENT_TIMESTAMP())
) src ON (tgt.event_id = src.event_id)
WHEN NOT MATCHED THEN INSERT
    (event_id, org_id, customer_id, event_type, feature_name, occurred_at)
    VALUES (src.event_id, src.org_id, src.customer_id, src.event_type, src.feature_name, src.occurred_at)
WHEN MATCHED THEN UPDATE SET feature_name = src.feature_name;

MERGE INTO AI.CHURN_SCORES tgt
USING (
    SELECT 'SCORE-DEMO-001' AS score_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 0.1500 AS churn_probability, 'LOW'    AS risk_level, PARSE_JSON('["baixo_engajamento_inicial","perfil_consolidado"]')          AS top_drivers, 'Manter cadência padrão e monitorar próxima renovação'                                   AS recommended_action, 18000.00 AS expected_revenue_at_risk, '1.0.0-lr' AS model_version UNION ALL
    SELECT 'SCORE-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 0.7200, 'HIGH',   PARSE_JSON('["multiplas_violacoes_sla","nps_muito_baixo","acumulo_de_tickets"]'),        'Escalar para time de CS sênior e revisar SLA',                                          68400.00,  '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 0.2200, 'LOW',    PARSE_JSON('["perfil_de_risco_moderado"]'),                                              'Manter cadência padrão e monitorar próxima renovação',                                  10560.00,  '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 0.8100, 'HIGH',   PARSE_JSON('["multiplas_violacoes_sla","inatividade_prolongada","nps_muito_baixo"]'),    'Contato imediato do CSM + oferta de desconto de retenção',                             162000.00, '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 0.3800, 'MEDIUM', PARSE_JSON('["perfil_de_risco_moderado","baixo_engajamento"]'),                          'Aumentar cadência de contato e revisar health score mensalmente',                       13680.00,  '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-006', 0.1200, 'LOW',    PARSE_JSON('["perfil_de_risco_moderado"]'),                                              'Manter cadência padrão e monitorar próxima renovação',                                   2160.00,   '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-007', 0.1900, 'LOW',    PARSE_JSON('["perfil_de_risco_moderado"]'),                                              'Manter cadência padrão e monitorar próxima renovação',                                   7980.00,   '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-009', 0.2900, 'LOW',    PARSE_JSON('["perfil_de_risco_moderado"]'),                                              'Manter cadência padrão e monitorar próxima renovação',                                  17400.00,  '1.0.0-lr' UNION ALL
    SELECT 'SCORE-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-010', 0.5500, 'MEDIUM', PARSE_JSON('["baixo_engajamento","health_score_crítico"]'),                              'Realizar NPS follow-up e coletar feedback detalhado',                                   82500.00,  '1.0.0-lr'
) src ON (tgt.score_id = src.score_id)
WHEN NOT MATCHED THEN INSERT
    (score_id, org_id, customer_id, churn_probability, risk_level, top_drivers, recommended_action, expected_revenue_at_risk, model_version)
    VALUES (src.score_id, src.org_id, src.customer_id, src.churn_probability, src.risk_level, src.top_drivers, src.recommended_action, src.expected_revenue_at_risk, src.model_version)
WHEN MATCHED THEN UPDATE SET churn_probability = src.churn_probability, risk_level = src.risk_level,
    top_drivers = src.top_drivers, recommended_action = src.recommended_action,
    expected_revenue_at_risk = src.expected_revenue_at_risk, scored_at = CURRENT_TIMESTAMP();

MERGE INTO AI.RECOMMENDATIONS tgt
USING (
    SELECT 'REC-DEMO-001' AS recommendation_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS entity_id, 'customer' AS entity_type, 'upsell'     AS recommendation_type, 'HIGH'   AS priority, 'Propor upgrade para Enterprise Suite Plus com módulo de BI avançado'             AS recommendation_text, 24000.00 AS expected_impact_usd, 0.82 AS confidence_score, 'CSM'   AS owner_role, 'pending' AS status, TRUE AS is_active UNION ALL
    SELECT 'REC-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-003', 'customer', 'expansion',  'MEDIUM', 'Adicionar 5 novos usuários ao plano Growth após adoção consistente',             12000.00, 0.71, 'Sales', 'pending', TRUE UNION ALL
    SELECT 'REC-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-005', 'customer', 'upsell',     'MEDIUM', 'Apresentar módulo de Document Intelligence — uso frequente detectado',            9600.00,  0.65, 'CSM',   'pending', TRUE UNION ALL
    SELECT 'REC-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-007', 'customer', 'renewal',    'HIGH',   'Iniciar negociação de renovação 90 dias antes — NPS alto, ótimo momento',        42000.00, 0.90, 'Sales', 'pending', TRUE UNION ALL
    SELECT 'REC-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-010', 'customer', 'expansion',  'LOW',    'Oferecer pacote adicional de Cortex AI tokens — alta utilização observada',       15000.00, 0.58, 'CSM',   'pending', TRUE
) src ON (tgt.recommendation_id = src.recommendation_id)
WHEN NOT MATCHED THEN INSERT
    (recommendation_id, org_id, entity_id, entity_type, recommendation_type, priority, recommendation_text, expected_impact_usd, confidence_score, owner_role, status, is_active)
    VALUES (src.recommendation_id, src.org_id, src.entity_id, src.entity_type, src.recommendation_type, src.priority, src.recommendation_text, src.expected_impact_usd, src.confidence_score, src.owner_role, src.status, src.is_active)
WHEN MATCHED THEN UPDATE SET status = src.status;

MERGE INTO CORE.TRANSACTIONS tgt
USING (
    SELECT 'TRX-DEMO-001' AS transaction_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'new_contract' AS transaction_type, 120000.00 AS amount, 'completed' AS status, '2026-01-01'::DATE AS transaction_date UNION ALL
    SELECT 'TRX-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 'new_contract', 95000.00,  'completed', '2025-10-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 'new_contract', 48000.00,  'completed', '2026-04-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 'new_contract', 200000.00, 'completed', '2025-09-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 'new_contract', 36000.00,  'completed', '2026-07-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-006', 'ORG-DEMO-001', 'CUST-DEMO-006', 'new_contract', 18000.00,  'completed', '2026-02-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-007', 'ORG-DEMO-001', 'CUST-DEMO-007', 'new_contract', 42000.00,  'completed', '2025-12-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-008', 'ORG-DEMO-001', 'CUST-DEMO-008', 'churn',        75000.00,  'completed', '2026-03-31'::DATE UNION ALL
    SELECT 'TRX-DEMO-009', 'ORG-DEMO-001', 'CUST-DEMO-009', 'new_contract', 60000.00,  'completed', '2026-03-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-010', 'ORG-DEMO-001', 'CUST-DEMO-010', 'new_contract', 150000.00, 'completed', '2025-11-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-011', 'ORG-DEMO-001', 'CUST-DEMO-001', 'upsell',       12000.00,  'completed', '2026-03-15'::DATE UNION ALL
    SELECT 'TRX-DEMO-012', 'ORG-DEMO-001', 'CUST-DEMO-003', 'expansion',    8000.00,   'completed', '2026-05-01'::DATE UNION ALL
    SELECT 'TRX-DEMO-013', 'ORG-DEMO-001', 'CUST-DEMO-007', 'renewal',      42000.00,  'completed', '2024-12-01'::DATE
) src ON (tgt.transaction_id = src.transaction_id)
WHEN NOT MATCHED THEN INSERT
    (transaction_id, org_id, customer_id, transaction_type, amount, status, transaction_date)
    VALUES (src.transaction_id, src.org_id, src.customer_id, src.transaction_type, src.amount, src.status, src.transaction_date)
WHEN MATCHED THEN UPDATE SET status = src.status;

-- Demo data: CORE.ACCOUNTS
MERGE INTO CORE.ACCOUNTS tgt
USING (
    SELECT 'ACC-DEMO-001' AS account_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'Acme Corp'          AS account_name, 'Enterprise'  AS account_type, 'Technology' AS industry, 5000 AS employee_count, 500000000.00 AS annual_revenue UNION ALL
    SELECT 'ACC-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 'Beta Saude S.A.',   'Enterprise',  'Healthcare',   2000,  180000000.00 UNION ALL
    SELECT 'ACC-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 'Gama Retail Ltda',  'Mid-Market',  'Retail',        800,   75000000.00 UNION ALL
    SELECT 'ACC-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 'Delta Finance',     'Enterprise',  'Financial',   10000, 2000000000.00 UNION ALL
    SELECT 'ACC-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 'Epsilon Educacao',  'Mid-Market',  'Education',     300,   30000000.00
) src ON (tgt.account_id = src.account_id)
WHEN NOT MATCHED THEN INSERT
    (account_id, org_id, customer_id, account_name, account_type, industry, employee_count, annual_revenue)
    VALUES (src.account_id, src.org_id, src.customer_id, src.account_name, src.account_type, src.industry, src.employee_count, src.annual_revenue)
WHEN MATCHED THEN UPDATE SET account_name = src.account_name;

-- Demo data: CORE.PRODUCTS
MERGE INTO CORE.PRODUCTS tgt
USING (
    SELECT 'PROD-001' AS product_id, 'ORG-DEMO-001' AS org_id, 'NEXUS AI DataOps — Enterprise'   AS product_name, 'Platform'   AS product_category, 10000.00 AS unit_price, TRUE AS is_active UNION ALL
    SELECT 'PROD-002', 'ORG-DEMO-001', 'NEXUS AI DataOps — Growth',    'Platform',   4000.00,  TRUE UNION ALL
    SELECT 'PROD-003', 'ORG-DEMO-001', 'NEXUS AI DataOps — Starter',   'Platform',   1500.00,  TRUE UNION ALL
    SELECT 'PROD-004', 'ORG-DEMO-001', 'Vertical Pack — Financeiro',   'Add-on',     2000.00,  TRUE UNION ALL
    SELECT 'PROD-005', 'ORG-DEMO-001', 'Vertical Pack — Varejo',       'Add-on',     2000.00,  TRUE UNION ALL
    SELECT 'PROD-006', 'ORG-DEMO-001', 'Cortex AI Tokens — 1M',        'Consumption', 500.00,  TRUE
) src ON (tgt.product_id = src.product_id)
WHEN NOT MATCHED THEN INSERT
    (product_id, org_id, product_name, product_category, unit_price, is_active)
    VALUES (src.product_id, src.org_id, src.product_name, src.product_category, src.unit_price, src.is_active)
WHEN MATCHED THEN UPDATE SET unit_price = src.unit_price;

-- Demo data: CORE.INTERACTIONS
MERGE INTO CORE.INTERACTIONS tgt
USING (
    SELECT 'INT-DEMO-001' AS interaction_id, 'ORG-DEMO-001' AS org_id, 'CUST-DEMO-001' AS customer_id, 'email'   AS channel, 'inbound'  AS direction, 'Interesse em upgrade Enterprise Plus' AS subject,  0.75 AS sentiment_score, 'qualified' AS outcome, DATEADD('day', -5, CURRENT_TIMESTAMP()) AS occurred_at UNION ALL
    SELECT 'INT-DEMO-002', 'ORG-DEMO-001', 'CUST-DEMO-002', 'call',    'outbound', 'QBR Q3 — revisao de SLA',                           -0.20, 'follow_up', DATEADD('day', -3, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'INT-DEMO-003', 'ORG-DEMO-001', 'CUST-DEMO-003', 'chat',    'inbound',  'Duvida sobre integracao com Salesforce',              0.50, 'resolved',  DATEADD('day', -2, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'INT-DEMO-004', 'ORG-DEMO-001', 'CUST-DEMO-004', 'meeting', 'outbound', 'Executive Business Review — Q2 2026',                0.30, 'committed', DATEADD('day', -7, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'INT-DEMO-005', 'ORG-DEMO-001', 'CUST-DEMO-005', 'email',   'inbound',  'Solicitacao de desconto na renovacao',               -0.10, 'pending',   DATEADD('day', -1, CURRENT_TIMESTAMP())
) src ON (tgt.interaction_id = src.interaction_id)
WHEN NOT MATCHED THEN INSERT
    (interaction_id, org_id, customer_id, channel, direction, subject, sentiment_score, outcome, occurred_at)
    VALUES (src.interaction_id, src.org_id, src.customer_id, src.channel, src.direction, src.subject, src.sentiment_score, src.outcome, src.occurred_at)
WHEN MATCHED THEN UPDATE SET subject = src.subject;

-- Demo data: MART.REVENUE_OPPORTUNITY_SCORE
MERGE INTO MART.REVENUE_OPPORTUNITY_SCORE tgt
USING (
    SELECT 'ROS-DEMO-001' AS score_id, 'CUST-DEMO-001' AS customer_id, 'ORG-DEMO-001' AS org_id, 0.85 AS opportunity_score, 'upsell'    AS opportunity_type, 30000.00 AS estimated_revenue_usd, 0.90 AS confidence UNION ALL
    SELECT 'ROS-DEMO-003', 'CUST-DEMO-003', 'ORG-DEMO-001', 0.70, 'upsell',    12000.00, 0.78 UNION ALL
    SELECT 'ROS-DEMO-005', 'CUST-DEMO-005', 'ORG-DEMO-001', 0.55, 'expansion',  3600.00, 0.62 UNION ALL
    SELECT 'ROS-DEMO-007', 'CUST-DEMO-007', 'ORG-DEMO-001', 0.80, 'upsell',    10500.00, 0.81 UNION ALL
    SELECT 'ROS-DEMO-009', 'CUST-DEMO-009', 'ORG-DEMO-001', 0.75, 'expansion', 15000.00, 0.77 UNION ALL
    SELECT 'ROS-DEMO-010', 'CUST-DEMO-010', 'ORG-DEMO-001', 0.20, 'retention',  7500.00, 0.45
) src ON (tgt.score_id = src.score_id)
WHEN NOT MATCHED THEN INSERT
    (score_id, customer_id, org_id, opportunity_score, opportunity_type, estimated_revenue_usd, confidence)
    VALUES (src.score_id, src.customer_id, src.org_id, src.opportunity_score, src.opportunity_type, src.estimated_revenue_usd, src.confidence)
WHEN MATCHED THEN UPDATE SET opportunity_score = src.opportunity_score;

-- Versão v2.0.0
MERGE INTO CONFIG.APP_SETTINGS t
USING (SELECT 'app_version' AS setting_key, '2.0.0' AS setting_value, 'NEXUS AI DataOps v2.0 — Data Onboarding & KBS' AS description) s
ON t.setting_key = s.setting_key
WHEN MATCHED THEN UPDATE SET setting_value = '2.0.0', updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description) VALUES (s.setting_key, s.setting_value, s.description);

-- ═══════════════════════════════════════════════════════════════════════════
-- SPRINT 3 — Semantic Models, Cortex Analyst & Multi-org
-- ═══════════════════════════════════════════════════════════════════════════

-- STAGING schema (necessário para DAGs Airflow criarem tabelas temporárias)
CREATE SCHEMA IF NOT EXISTS STAGING;
GRANT USAGE ON SCHEMA STAGING TO APPLICATION ROLE NEXUS_ADMIN;
GRANT USAGE ON SCHEMA STAGING TO APPLICATION ROLE NEXUS_ANALYST;
GRANT CREATE TABLE ON SCHEMA STAGING TO APPLICATION ROLE NEXUS_ADMIN;

-- AI.AGENT_MEMORY — estado multi-turn de agentes Cortex (P2)
CREATE TABLE IF NOT EXISTS AI.AGENT_MEMORY (
    memory_id       VARCHAR(36)   DEFAULT UUID_STRING() PRIMARY KEY,
    org_id          VARCHAR(64)   NOT NULL,
    user_name       VARCHAR(128)  NOT NULL,
    agent_name      VARCHAR(64)   NOT NULL,
    session_id      VARCHAR(36),
    memory_key      VARCHAR(256)  NOT NULL,
    memory_value    VARIANT,
    created_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    expires_at      TIMESTAMP_TZ
);

EXECUTE IMMEDIATE $$
BEGIN
    ALTER TABLE AI.AGENT_MEMORY ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SKIPPED: ' || SQLERRM;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE AI.AGENT_MEMORY TO APPLICATION ROLE NEXUS_ANALYST;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE AI.AGENT_MEMORY TO APPLICATION ROLE NEXUS_ADMIN;

-- Demo data: ORG-DEMO-002 — 3 clientes SMB LATAM (high churn, contraste com ORG-DEMO-001)
MERGE INTO CORE.CUSTOMERS t
USING (
    SELECT 'CUST-DEMO-011' AS customer_id, 'ORG-DEMO-002' AS org_id,
           'Kappa Varejo LTDA'    AS name, 'admin@kappa-varejo.com' AS email,
           'SMB' AS segment, 'LATAM' AS region, 'Retail' AS industry,
           'at_risk' AS lifecycle_stage,
           12000.00 AS arr, 1000.00 AS mrr, 8 AS nps_score,
           '2026-07-31'::DATE AS contract_end_date UNION ALL
    SELECT 'CUST-DEMO-012', 'ORG-DEMO-002',
           'Lambda Serviços S.A.', 'ti@lambda-servicos.com.br',
           'SMB', 'LATAM', 'Services', 'at_risk',
           9600.00, 800.00, 15, '2026-08-31'::DATE UNION ALL
    SELECT 'CUST-DEMO-013', 'ORG-DEMO-002',
           'Mu Construção e Engenharia', 'operacoes@mu-const.com',
           'SMB', 'LATAM', 'Construction', 'active',
           14400.00, 1200.00, 32, '2027-02-28'::DATE
) s ON (t.customer_id = s.customer_id)
WHEN NOT MATCHED THEN INSERT
    (customer_id, org_id, name, email, segment, region, industry,
     lifecycle_stage, arr, mrr, nps_score, contract_end_date)
    VALUES (s.customer_id, s.org_id, s.name, s.email, s.segment, s.region,
            s.industry, s.lifecycle_stage, s.arr, s.mrr, s.nps_score, s.contract_end_date);

-- Demo data: ORG-USER-MAP para ORG-DEMO-002
MERGE INTO CONFIG.ORG_USER_MAP t
USING (
    SELECT 'ORG-DEMO-002' AS org_id, 'NEXUS_ANALYST_2' AS user_name, 'analyst' AS role UNION ALL
    SELECT 'ORG-DEMO-002', 'NEXUS_ADMIN', 'admin'
) s ON (t.org_id = s.org_id AND t.user_name = s.user_name)
WHEN NOT MATCHED THEN INSERT (org_id, user_name, role) VALUES (s.org_id, s.user_name, s.role);

-- Demo data: Tickets ORG-DEMO-002 (alta prioridade — evidencia RAP isolation)
MERGE INTO CORE.TICKETS t
USING (
    SELECT 'TKT-DEMO-021' AS ticket_id, 'ORG-DEMO-002' AS org_id, 'CUST-DEMO-011' AS customer_id,
           'open' AS status, 'urgent' AS priority, 'bug' AS ticket_type,
           'Falha crítica na ingestão de dados de vendas' AS subject,
           DATEADD('hour', -48, CURRENT_TIMESTAMP()) AS created_at UNION ALL
    SELECT 'TKT-DEMO-022', 'ORG-DEMO-002', 'CUST-DEMO-011',
           'open', 'high', 'support',
           'Dashboard executivo não carrega para usuários mobile',
           DATEADD('hour', -24, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'TKT-DEMO-023', 'ORG-DEMO-002', 'CUST-DEMO-012',
           'open', 'urgent', 'billing',
           'Cobrança duplicada em Junho — cliente ameaça cancelar',
           DATEADD('hour', -6, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'TKT-DEMO-024', 'ORG-DEMO-002', 'CUST-DEMO-013',
           'in_progress', 'medium', 'feature_request',
           'Solicita integração com ERP SAP',
           DATEADD('day', -3, CURRENT_TIMESTAMP())
) s ON (t.ticket_id = s.ticket_id)
WHEN NOT MATCHED THEN INSERT
    (ticket_id, org_id, customer_id, status, priority, ticket_type, subject, created_at)
    VALUES (s.ticket_id, s.org_id, s.customer_id, s.status, s.priority,
            s.ticket_type, s.subject, s.created_at);

-- Demo data: Interações ORG-DEMO-002 (sentimento negativo — churn em progresso)
MERGE INTO CORE.INTERACTIONS t
USING (
    SELECT 'INT-DEMO-021' AS interaction_id, 'ORG-DEMO-002' AS org_id,
           'CUST-DEMO-011' AS customer_id, 'call' AS channel, 'inbound' AS direction,
           'Reclamação sobre instabilidade da plataforma nas últimas 2 semanas' AS subject,
           -0.65 AS sentiment_score, 'follow_up' AS outcome,
           DATEADD('day', -2, CURRENT_TIMESTAMP()) AS occurred_at UNION ALL
    SELECT 'INT-DEMO-022', 'ORG-DEMO-002', 'CUST-DEMO-012', 'email', 'inbound',
           'Solicitação de rescisão antecipada — aguardando proposta de retenção',
           -0.80, 'pending', DATEADD('day', -1, CURRENT_TIMESTAMP()) UNION ALL
    SELECT 'INT-DEMO-023', 'ORG-DEMO-002', 'CUST-DEMO-013', 'meeting', 'outbound',
           'QBR Q2 — apresentação de ROI positivo, cliente satisfeito com resultados',
           0.55, 'committed', DATEADD('day', -5, CURRENT_TIMESTAMP())
) s ON (t.interaction_id = s.interaction_id)
WHEN NOT MATCHED THEN INSERT
    (interaction_id, org_id, customer_id, channel, direction, subject,
     sentiment_score, outcome, occurred_at)
    VALUES (s.interaction_id, s.org_id, s.customer_id, s.channel, s.direction,
            s.subject, s.sentiment_score, s.outcome, s.occurred_at);

-- Versão v3.0.0
MERGE INTO CONFIG.APP_SETTINGS t
USING (SELECT 'app_version' AS setting_key, '3.0.0' AS setting_value,
              'NEXUS AI DataOps v3.0 — Semantic Models, Cortex Analyst & Multi-org' AS description) s
ON t.setting_key = s.setting_key
WHEN MATCHED THEN UPDATE SET setting_value = '3.0.0', updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description)
    VALUES (s.setting_key, s.setting_value, s.description);
