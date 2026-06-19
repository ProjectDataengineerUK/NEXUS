-- NEXUS AI DataOps — Tabelas canônicas ausentes (CONTEXT.md seção 34)
-- Sprint 2 — P1: CORE.ACCOUNTS, CORE.PRODUCTS, CORE.INTERACTIONS
-- Este arquivo é para deploy direto (sem Native App). O equivalente está em setup_script.sql.

USE DATABASE NEXUS_APP;
USE SCHEMA CORE;

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
    CONSTRAINT pk_accounts PRIMARY KEY (account_id),
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) REFERENCES CORE.CUSTOMERS(customer_id)
);

COMMENT ON TABLE CORE.ACCOUNTS IS 'Contas corporativas — empresa/conta CRM do cliente';
COMMENT ON COLUMN CORE.ACCOUNTS.org_id IS 'Tenant isolado via RAP_ORG_ISOLATION';
COMMENT ON COLUMN CORE.ACCOUNTS.customer_id IS 'FK para CORE.CUSTOMERS (contato principal)';

CREATE TABLE IF NOT EXISTS CORE.PRODUCTS (
    product_id       VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id           VARCHAR(50)   NOT NULL,
    product_name     VARCHAR(255)  NOT NULL,
    product_category VARCHAR(100),
    description      TEXT,
    unit_price       DECIMAL(18,2),
    currency         VARCHAR(10)   DEFAULT 'USD',
    billing_model    VARCHAR(50)   DEFAULT 'subscription',
    is_active        BOOLEAN       DEFAULT TRUE,
    created_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_products PRIMARY KEY (product_id)
);

COMMENT ON TABLE CORE.PRODUCTS IS 'Catalogo de produtos/planos vendidos pelo provider';

CREATE TABLE IF NOT EXISTS CORE.INTERACTIONS (
    interaction_id   VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    org_id           VARCHAR(50)   NOT NULL,
    customer_id      VARCHAR(36),
    account_id       VARCHAR(36),
    channel          VARCHAR(50)   CHECK (channel IN ('email','call','chat','meeting','sms','social','other')),
    direction        VARCHAR(10)   CHECK (direction IN ('inbound','outbound')),
    subject          VARCHAR(500),
    body             TEXT,
    sentiment_score  DECIMAL(4,2)  CHECK (sentiment_score BETWEEN -1 AND 1),
    outcome          VARCHAR(100),
    duration_minutes INTEGER,
    owner_user       VARCHAR(255),
    occurred_at      TIMESTAMP_TZ  NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    created_at       TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_interactions PRIMARY KEY (interaction_id),
    CONSTRAINT fk_interactions_customer FOREIGN KEY (customer_id) REFERENCES CORE.CUSTOMERS(customer_id)
);

COMMENT ON TABLE CORE.INTERACTIONS IS 'Histórico de interações com clientes (emails, calls, meetings)';
COMMENT ON COLUMN CORE.INTERACTIONS.sentiment_score IS 'Preenchido pelo pipeline de NLP (-1 negativo, 1 positivo)';

-- Aplicar RAP (deve existir no setup_script ou 08_row_access_policies.sql)
ALTER TABLE CORE.ACCOUNTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
ALTER TABLE CORE.PRODUCTS     ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);
ALTER TABLE CORE.INTERACTIONS ADD ROW ACCESS POLICY CORE.RAP_ORG_ISOLATION ON (org_id);

-- GRANTs
GRANT SELECT ON TABLE CORE.ACCOUNTS     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE CORE.PRODUCTS     TO APPLICATION ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE CORE.INTERACTIONS TO APPLICATION ROLE NEXUS_VIEWER;
GRANT INSERT, UPDATE ON TABLE CORE.ACCOUNTS     TO APPLICATION ROLE NEXUS_ADMIN;
GRANT INSERT, UPDATE ON TABLE CORE.PRODUCTS     TO APPLICATION ROLE NEXUS_ADMIN;
GRANT INSERT, UPDATE ON TABLE CORE.INTERACTIONS TO APPLICATION ROLE NEXUS_ADMIN;
