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
    customer_id     VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)  NOT NULL,
    name            VARCHAR(500) NOT NULL,
    email           VARCHAR(500),
    phone           VARCHAR(50),
    segment         VARCHAR(50),
    region          VARCHAR(100),
    industry        VARCHAR(100),
    status          VARCHAR(50)  DEFAULT 'active',
    lifecycle_stage VARCHAR(50)  DEFAULT 'active',
    nps_score       INTEGER,
    customer_since  TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at      TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (customer_id)
);

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
    sla_breached    BOOLEAN       DEFAULT FALSE,
    sentiment_score DECIMAL(4,3),
    created_at      TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    resolved_at     TIMESTAMP_TZ,
    PRIMARY KEY (ticket_id)
);

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
    document_id       VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id            VARCHAR(36)  NOT NULL,
    entity_id         VARCHAR(36),
    entity_type       VARCHAR(50),
    document_name     VARCHAR(500) NOT NULL,
    document_type     VARCHAR(100) NOT NULL DEFAULT 'other',
    stage_path        VARCHAR(1000),
    processing_status VARCHAR(50)  DEFAULT 'pending',
    summary           TEXT,
    created_at        TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (document_id)
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
