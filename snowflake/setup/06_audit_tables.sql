-- NEXUS AI DataOps — Audit & Governance Tables

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.PROMPT_LOG (
    log_id              VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    session_id          VARCHAR(36),
    org_id              VARCHAR(36)     NOT NULL,
    user_name           VARCHAR(255)    NOT NULL,
    role_name           VARCHAR(255)    NOT NULL,
    agent_id            VARCHAR(100),
    prompt_text         TEXT            NOT NULL,
    data_sources        VARIANT,
    response_summary    TEXT,
    cortex_tokens_used  INTEGER         DEFAULT 0,
    latency_ms          INTEGER,
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (log_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.ACCESS_LOG (
    access_id       VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    user_name       VARCHAR(255)    NOT NULL,
    role_name       VARCHAR(255)    NOT NULL,
    resource_type   VARCHAR(100)    NOT NULL,
    resource_name   VARCHAR(500)    NOT NULL,
    action          VARCHAR(50)     NOT NULL,
    success         BOOLEAN         NOT NULL DEFAULT TRUE,
    ip_address      VARCHAR(50),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (access_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.ACTION_LOG (
    action_id           VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id              VARCHAR(36)     NOT NULL,
    user_name           VARCHAR(255)    NOT NULL,
    role_name           VARCHAR(255)    NOT NULL,
    action_type         VARCHAR(100)    NOT NULL,
    entity_type         VARCHAR(50),
    entity_id           VARCHAR(36),
    payload             VARIANT,
    status              VARCHAR(50)     DEFAULT 'pending',
    external_system     VARCHAR(100),
    external_id         VARCHAR(255),
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    executed_at         TIMESTAMP_TZ,
    PRIMARY KEY (action_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS (
    result_id       VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    table_name      VARCHAR(255)    NOT NULL,
    metric_name     VARCHAR(255)    NOT NULL,
    metric_value    DECIMAL(18,6),
    threshold       DECIMAL(18,6),
    status          VARCHAR(20)     NOT NULL DEFAULT 'PASS',
    details         VARIANT,
    measured_at     TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (result_id),
    CONSTRAINT chk_dq_status CHECK (status IN ('PASS', 'WARN', 'FAIL'))
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CONFIG.INGEST_LOG (
    ingest_id       VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    source_system   VARCHAR(100)    NOT NULL,
    table_target    VARCHAR(255)    NOT NULL,
    rows_loaded     INTEGER         DEFAULT 0,
    rows_failed     INTEGER         DEFAULT 0,
    status          VARCHAR(20)     NOT NULL DEFAULT 'running',
    error_message   TEXT,
    started_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    completed_at    TIMESTAMP_TZ,
    PRIMARY KEY (ingest_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CONFIG.APP_SETTINGS (
    setting_key     VARCHAR(255)    NOT NULL,
    setting_value   VARCHAR(2000)   NOT NULL,
    description     TEXT,
    updated_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (setting_key)
);

MERGE INTO NEXUS_APP.CONFIG.APP_SETTINGS AS tgt
USING (
    SELECT 'default_llm_model'       AS k, 'claude-3-5-sonnet'  AS v, 'Modelo LLM padrão para agentes Cortex'         AS d
    UNION ALL SELECT 'ui_warehouse',            'NEXUS_UI_WH',          'Warehouse para Streamlit UI'
    UNION ALL SELECT 'compute_warehouse',       'NEXUS_COMPUTE_WH',     'Warehouse para queries e agentes'
    UNION ALL SELECT 'ml_warehouse',            'NEXUS_ML_WH',          'Warehouse para treino de modelos ML'
    UNION ALL SELECT 'churn_high_threshold',    '0.7',                  'Score acima = risco HIGH'
    UNION ALL SELECT 'churn_medium_threshold',  '0.4',                  'Score acima = risco MEDIUM'
    UNION ALL SELECT 'freshness_sla_hours',     '24',                   'Horas máx sem refresh antes de alerta'
    UNION ALL SELECT 'agent_max_tokens',        '2048',                 'Max tokens por resposta de agente'
    UNION ALL SELECT 'agent_temperature',       '0.1',                  'Temperature para respostas determinísticas'
    UNION ALL SELECT 'audit_retention_days',    '365',                  'Retenção de logs de auditoria'
    UNION ALL SELECT 'vertical_pack',           'saas_customer',        'Vertical Pack ativo'
    UNION ALL SELECT 'enable_workflow_automation', 'false',             'Habilitar M7 Automation (External Access)'
    UNION ALL SELECT 'demo_mode',               'false',                'Usar dataset demo em vez de dados reais'
) AS src ON tgt.setting_key = src.k
WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, description, updated_at)
    VALUES (src.k, src.v, src.d, CURRENT_TIMESTAMP());

ALTER TABLE NEXUS_APP.AUDIT.PROMPT_LOG    CLUSTER BY (org_id, created_at);
ALTER TABLE NEXUS_APP.AUDIT.ACCESS_LOG    CLUSTER BY (org_id, created_at);
ALTER TABLE NEXUS_APP.AUDIT.ACTION_LOG    CLUSTER BY (org_id, created_at);
