-- =============================================================================
-- NEXUS AI DataOps — PII Tagging & Data Classification (Horizon Catalog)
-- Object tags para PII + auto-classification + lineage anchors
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA GOVERNANCE;

-- ─── Tags de classificação de dados ──────────────────────────────────────────

CREATE TAG IF NOT EXISTS GOVERNANCE.PII
    ALLOWED_VALUES 'DIRECT', 'QUASI', 'SENSITIVE', 'NONE'
    COMMENT = 'PII classification per LGPD/GDPR — DIRECT=names/emails/CPF, QUASI=zip/age, SENSITIVE=health/finance';

CREATE TAG IF NOT EXISTS GOVERNANCE.DATA_DOMAIN
    ALLOWED_VALUES 'CUSTOMER', 'FINANCIAL', 'OPERATIONAL', 'AI_OUTPUT', 'AUDIT', 'SYSTEM'
    COMMENT = 'Business domain of the table or column';

CREATE TAG IF NOT EXISTS GOVERNANCE.RETENTION_DAYS
    COMMENT = 'Data retention requirement in days (e.g. "2555" = 7 years)';

CREATE TAG IF NOT EXISTS GOVERNANCE.COMPLIANCE
    ALLOWED_VALUES 'LGPD', 'GDPR', 'SOC2', 'HIPAA', 'PCI_DSS', 'INTERNAL'
    COMMENT = 'Compliance regime governing this column';


-- ─── Aplicar tags em CORE.CUSTOMERS ──────────────────────────────────────────

ALTER TABLE CORE.CUSTOMERS
    MODIFY COLUMN email
        SET TAG GOVERNANCE.PII = 'DIRECT',
                GOVERNANCE.COMPLIANCE = 'LGPD';

ALTER TABLE CORE.CUSTOMERS
    MODIFY COLUMN phone
        SET TAG GOVERNANCE.PII = 'DIRECT',
                GOVERNANCE.COMPLIANCE = 'LGPD';

ALTER TABLE CORE.CUSTOMERS
    MODIFY COLUMN name
        SET TAG GOVERNANCE.PII = 'DIRECT';

ALTER TABLE CORE.CUSTOMERS
    MODIFY COLUMN billing_address
        SET TAG GOVERNANCE.PII = 'QUASI';

ALTER TABLE CORE.CUSTOMERS
    SET TAG
        GOVERNANCE.DATA_DOMAIN    = 'CUSTOMER',
        GOVERNANCE.RETENTION_DAYS = '2555';


-- ─── Aplicar tags em CORE.CONTACTS ───────────────────────────────────────────

ALTER TABLE CORE.CONTACTS
    MODIFY COLUMN email
        SET TAG GOVERNANCE.PII = 'DIRECT',
                GOVERNANCE.COMPLIANCE = 'LGPD';

ALTER TABLE CORE.CONTACTS
    MODIFY COLUMN phone
        SET TAG GOVERNANCE.PII = 'DIRECT',
                GOVERNANCE.COMPLIANCE = 'LGPD';

ALTER TABLE CORE.CONTACTS
    MODIFY COLUMN first_name
        SET TAG GOVERNANCE.PII = 'DIRECT';

ALTER TABLE CORE.CONTACTS
    MODIFY COLUMN last_name
        SET TAG GOVERNANCE.PII = 'DIRECT';


-- ─── Aplicar tags em CORE.AUDIT_LOG ──────────────────────────────────────────

ALTER TABLE CORE.AUDIT_LOG
    SET TAG
        GOVERNANCE.DATA_DOMAIN    = 'AUDIT',
        GOVERNANCE.RETENTION_DAYS = '2555';

ALTER TABLE CORE.AUDIT_LOG
    MODIFY COLUMN user_name
        SET TAG GOVERNANCE.PII = 'QUASI';

ALTER TABLE CORE.AUDIT_LOG
    MODIFY COLUMN prompt_text
        SET TAG GOVERNANCE.PII = 'SENSITIVE',
                GOVERNANCE.COMPLIANCE = 'LGPD';


-- ─── Aplicar tags em AI.CHURN_SCORES ─────────────────────────────────────────

ALTER TABLE AI.CHURN_SCORES
    SET TAG GOVERNANCE.DATA_DOMAIN = 'AI_OUTPUT';


-- ─── Aplicar tags em AI.RECOMMENDATIONS ──────────────────────────────────────

ALTER TABLE AI.RECOMMENDATIONS
    SET TAG GOVERNANCE.DATA_DOMAIN = 'AI_OUTPUT';


-- ─── View: inventário de colunas PII ─────────────────────────────────────────

CREATE OR REPLACE VIEW GOVERNANCE.V_PII_INVENTORY AS
SELECT
    t.object_database   AS database_name,
    t.object_schema     AS schema_name,
    t.object_name       AS table_name,
    t.column_name,
    t.tag_value         AS pii_level,
    t.tag_database      AS tag_db,
    t.tag_schema        AS tag_schema_name,
    t.tag_name
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'NEXUS_APP.CORE.CUSTOMERS', 'table'
    )
) t
WHERE t.tag_name = 'PII'

UNION ALL

SELECT
    t.object_database,
    t.object_schema,
    t.object_name,
    t.column_name,
    t.tag_value,
    t.tag_database,
    t.tag_schema,
    t.tag_name
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'NEXUS_APP.CORE.CONTACTS', 'table'
    )
) t
WHERE t.tag_name = 'PII';


-- ─── Auto-classification schedule (Snowflake Data Classification) ────────────

-- Inicia classificação automática nas tabelas core
CALL SYSTEM$CLASSIFY('NEXUS_APP.CORE.CUSTOMERS',  {'auto_tag': true});
CALL SYSTEM$CLASSIFY('NEXUS_APP.CORE.CONTACTS',   {'auto_tag': true});
CALL SYSTEM$CLASSIFY('NEXUS_APP.CORE.AUDIT_LOG',  {'auto_tag': true});
