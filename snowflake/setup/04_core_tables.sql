-- NEXUS AI DataOps — Core Tables (entidades consolidadas)

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA NEXUS_APP.CORE;

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.CUSTOMERS (
    customer_id         VARCHAR(36)     NOT NULL,
    org_id              VARCHAR(36)     NOT NULL,
    name                VARCHAR(255)    NOT NULL,
    email               VARCHAR(255),
    phone               VARCHAR(50),
    segment             VARCHAR(50)     NOT NULL DEFAULT 'SMB',
    region              VARCHAR(100),
    industry            VARCHAR(100),
    lifecycle_stage     VARCHAR(50)     NOT NULL DEFAULT 'active',
    arr                 DECIMAL(18,2),
    mrr                 DECIMAL(18,2),
    contract_start_date DATE,
    contract_end_date   DATE,
    nps_score           INTEGER,
    source_system       VARCHAR(50),
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.PRODUCTS (
    product_id      VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    name            VARCHAR(255)    NOT NULL,
    category        VARCHAR(100),
    unit_price      DECIMAL(18,2),
    currency        VARCHAR(10)     DEFAULT 'USD',
    is_active       BOOLEAN         DEFAULT TRUE,
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (product_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.TRANSACTIONS (
    transaction_id  VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    customer_id     VARCHAR(36)     NOT NULL,
    product_id      VARCHAR(36),
    amount          DECIMAL(18,2)   NOT NULL,
    currency        VARCHAR(10)     DEFAULT 'USD',
    transaction_type VARCHAR(50),
    status          VARCHAR(50)     DEFAULT 'completed',
    transaction_date DATE           NOT NULL,
    source_system   VARCHAR(50),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (transaction_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.TICKETS (
    ticket_id       VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    customer_id     VARCHAR(36)     NOT NULL,
    subject         VARCHAR(500),
    description     TEXT,
    status          VARCHAR(50)     NOT NULL DEFAULT 'open',
    priority        VARCHAR(20)     NOT NULL DEFAULT 'normal',
    sentiment_score DECIMAL(4,3),
    sentiment_label VARCHAR(20),
    resolved_at     TIMESTAMP_TZ,
    sla_breach      BOOLEAN         DEFAULT FALSE,
    source_system   VARCHAR(50),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (ticket_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.CONTRACTS (
    contract_id     VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    customer_id     VARCHAR(36)     NOT NULL,
    contract_name   VARCHAR(500),
    contract_value  DECIMAL(18,2),
    start_date      DATE,
    end_date        DATE,
    auto_renewal    BOOLEAN         DEFAULT FALSE,
    status          VARCHAR(50)     DEFAULT 'active',
    document_id     VARCHAR(36),
    extracted_fields VARIANT,
    risk_flags      VARIANT,
    source_system   VARCHAR(50),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (contract_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.DOCUMENTS (
    document_id     VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    entity_id       VARCHAR(36),
    entity_type     VARCHAR(50),
    document_name   VARCHAR(500)    NOT NULL,
    document_type   VARCHAR(100),
    file_size_bytes INTEGER,
    stage_path      VARCHAR(1000),
    extracted_text  TEXT,
    extracted_fields VARIANT,
    summary         TEXT,
    risk_flags      VARIANT,
    processing_status VARCHAR(50)   DEFAULT 'pending',
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    processed_at    TIMESTAMP_TZ,
    PRIMARY KEY (document_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.INTERACTIONS (
    interaction_id  VARCHAR(36)     NOT NULL,
    org_id          VARCHAR(36)     NOT NULL,
    customer_id     VARCHAR(36)     NOT NULL,
    channel         VARCHAR(50),
    interaction_type VARCHAR(50),
    direction       VARCHAR(10)     DEFAULT 'inbound',
    subject         VARCHAR(500),
    body_summary    TEXT,
    sentiment_score DECIMAL(4,3),
    sentiment_label VARCHAR(20),
    created_at      TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (interaction_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.SUBSCRIPTIONS (
    subscription_id     VARCHAR(36)     NOT NULL,
    org_id              VARCHAR(36)     NOT NULL,
    customer_id         VARCHAR(36)     NOT NULL,
    product_id          VARCHAR(36),
    plan_name           VARCHAR(255)    NOT NULL,
    plan_tier           VARCHAR(50)     NOT NULL DEFAULT 'standard',
    status              VARCHAR(50)     NOT NULL DEFAULT 'active',
    seats               INTEGER         DEFAULT 1,
    mrr                 DECIMAL(18,2),
    arr                 DECIMAL(18,2),
    trial_end_date      DATE,
    current_period_start DATE,
    current_period_end  DATE,
    cancel_at           DATE,
    canceled_at         TIMESTAMP_TZ,
    source_system       VARCHAR(50),
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (subscription_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

CREATE TABLE IF NOT EXISTS NEXUS_APP.CORE.PRODUCT_EVENTS (
    event_id            VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    org_id              VARCHAR(36)     NOT NULL,
    customer_id         VARCHAR(36)     NOT NULL,
    subscription_id     VARCHAR(36),
    event_type          VARCHAR(100)    NOT NULL,
    feature_name        VARCHAR(255),
    event_value         DECIMAL(18,4),
    properties          VARIANT,
    session_id          VARCHAR(36),
    user_id             VARCHAR(255),
    platform            VARCHAR(50),
    occurred_at         TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    created_at          TIMESTAMP_TZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_id),
    FOREIGN KEY (customer_id) REFERENCES NEXUS_APP.CORE.CUSTOMERS(customer_id)
);

-- Índices de busca (clustering keys para performance)
ALTER TABLE NEXUS_APP.CORE.CUSTOMERS       CLUSTER BY (org_id, lifecycle_stage);
ALTER TABLE NEXUS_APP.CORE.TRANSACTIONS    CLUSTER BY (org_id, transaction_date);
ALTER TABLE NEXUS_APP.CORE.TICKETS         CLUSTER BY (org_id, created_at);
ALTER TABLE NEXUS_APP.CORE.CONTRACTS       CLUSTER BY (org_id, end_date);
ALTER TABLE NEXUS_APP.CORE.SUBSCRIPTIONS   CLUSTER BY (org_id, status);
ALTER TABLE NEXUS_APP.CORE.PRODUCT_EVENTS  CLUSTER BY (org_id, occurred_at);
