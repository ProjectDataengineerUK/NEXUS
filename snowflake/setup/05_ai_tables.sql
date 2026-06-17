-- NEXUS AI DataOps — AI Layer Tables

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.CHURN_SCORES (
    score_id                VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id                  VARCHAR(36)     NOT NULL,
    customer_id             VARCHAR(36)     NOT NULL,
    churn_probability       DECIMAL(5,4)    NOT NULL,
    risk_level              VARCHAR(10)     NOT NULL,
    top_drivers             VARIANT,
    recommended_action      VARCHAR(1000),
    expected_revenue_at_risk DECIMAL(18,2),
    model_version           VARCHAR(50),
    scored_at               TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (score_id),
    CONSTRAINT chk_churn_prob CHECK (churn_probability BETWEEN 0 AND 1),
    CONSTRAINT chk_risk_level CHECK (risk_level IN ('HIGH', 'MEDIUM', 'LOW'))
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.RECOMMENDATIONS (
    recommendation_id   VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id              VARCHAR(36)     NOT NULL,
    entity_id           VARCHAR(36)     NOT NULL,
    entity_type         VARCHAR(50)     NOT NULL DEFAULT 'customer',
    recommendation_type VARCHAR(100)    NOT NULL,
    priority            VARCHAR(10)     NOT NULL DEFAULT 'MEDIUM',
    recommendation_text TEXT            NOT NULL,
    expected_impact_usd DECIMAL(18,2),
    confidence_score    DECIMAL(4,3),
    owner_role          VARCHAR(100),
    status              VARCHAR(50)     DEFAULT 'pending',
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    expires_at          TIMESTAMP_TZ,
    acted_at            TIMESTAMP_TZ,
    PRIMARY KEY (recommendation_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.AGENT_SESSIONS (
    session_id      VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    user_name       VARCHAR(255)    NOT NULL,
    user_role       VARCHAR(255)    NOT NULL,
    agent_id        VARCHAR(100)    NOT NULL,
    vertical_pack   VARCHAR(100)    NOT NULL DEFAULT 'saas_customer',
    started_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ended_at        TIMESTAMP_TZ,
    message_count   INTEGER         DEFAULT 0,
    total_tokens    INTEGER         DEFAULT 0,
    PRIMARY KEY (session_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.AGENT_MESSAGES (
    message_id      VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    session_id      VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    role            VARCHAR(20)     NOT NULL,
    content         TEXT            NOT NULL,
    tool_calls      VARIANT,
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (message_id),
    FOREIGN KEY (session_id) REFERENCES NEXUS_APP.AI.AGENT_SESSIONS(session_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.DOCUMENT_CHUNKS (
    chunk_id        VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    document_id     VARCHAR(36)     NOT NULL,
    document_name   VARCHAR(500),
    document_type   VARCHAR(100),
    chunk_index     INTEGER         NOT NULL,
    chunk_text      TEXT            NOT NULL,
    page_number     INTEGER,
    section_title   VARCHAR(500),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (chunk_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.AI.REVENUE_FORECAST (
    forecast_id     VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)     NOT NULL,
    forecast_date   DATE            NOT NULL,
    forecast_period VARCHAR(20)     NOT NULL DEFAULT 'monthly',
    predicted_arr   DECIMAL(18,2),
    predicted_mrr   DECIMAL(18,2),
    lower_bound     DECIMAL(18,2),
    upper_bound     DECIMAL(18,2),
    confidence      DECIMAL(4,3),
    model_version   VARCHAR(50),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (forecast_id)
);

ALTER TABLE NEXUS_APP.AI.CHURN_SCORES    CLUSTER BY (org_id, scored_at);
ALTER TABLE NEXUS_APP.AI.DOCUMENT_CHUNKS CLUSTER BY (org_id, document_id);
ALTER TABLE NEXUS_APP.AI.AGENT_MESSAGES  CLUSTER BY (session_id, created_at);
