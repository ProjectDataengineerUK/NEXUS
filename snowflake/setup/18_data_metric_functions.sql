-- NEXUS AI DataOps — Data Metric Functions (DMFs)
-- Qualidade automática de dados nas tabelas core.
-- Snowflake executa as DMFs no schedule configurado e persiste resultados em
-- SNOWFLAKE.LOCAL.DATA_METRIC_FUNCTION_REFERENCES (consultável via view abaixo).

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA GOVERNANCE;

-- ─────────────────────────────────────────────────────────────────────────────
-- DMF 1: Contagem de NULLs em qualquer coluna
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_NULL_COUNT(
    ARG_T TABLE(COL_1 VARCHAR)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT_IF(COL_1 IS NULL) FROM ARG_T
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- DMF 2: Freshness — horas desde o registro mais recente
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_FRESHNESS_HOURS(
    ARG_T TABLE(TS_COL TIMESTAMP_TZ)
)
RETURNS NUMBER
AS
$$
    SELECT DATEDIFF('hour', MAX(TS_COL), CURRENT_TIMESTAMP()) FROM ARG_T
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- DMF 3: Duplicados em coluna de chave primária
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.DMF_DUPLICATE_COUNT(
    ARG_T TABLE(KEY_COL VARCHAR)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*) - COUNT(DISTINCT KEY_COL) FROM ARG_T
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Associar DMFs às tabelas CORE
-- ─────────────────────────────────────────────────────────────────────────────

-- CORE.CUSTOMERS
ALTER TABLE CORE.CUSTOMERS SET DATA_METRIC_SCHEDULE = '60 MINUTE';

ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (customer_id);

ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (org_id);

ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (email);

ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_DUPLICATE_COUNT ON (customer_id);

ALTER TABLE CORE.CUSTOMERS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_FRESHNESS_HOURS ON (created_at);

-- CORE.TRANSACTIONS
ALTER TABLE CORE.TRANSACTIONS SET DATA_METRIC_SCHEDULE = '60 MINUTE';

ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (transaction_id);

ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (customer_id);

ALTER TABLE CORE.TRANSACTIONS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_FRESHNESS_HOURS ON (transaction_date);

-- CORE.TICKETS
ALTER TABLE CORE.TICKETS SET DATA_METRIC_SCHEDULE = '60 MINUTE';

ALTER TABLE CORE.TICKETS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_NULL_COUNT ON (ticket_id);

ALTER TABLE CORE.TICKETS ADD DATA METRIC FUNCTION
    GOVERNANCE.DMF_FRESHNESS_HOURS ON (created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- View de monitoramento de qualidade (consolida resultados de todas as DMFs)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD AS
SELECT
    measurement_time,
    table_schema,
    table_name,
    metric_name,
    column_name,
    value,
    CASE
        WHEN metric_name = 'DMF_NULL_COUNT'       AND value > 0   THEN 'WARN'
        WHEN metric_name = 'DMF_DUPLICATE_COUNT'  AND value > 0   THEN 'FAIL'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 24  THEN 'WARN'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 48  THEN 'FAIL'
        ELSE 'OK'
    END                                                             AS quality_status
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE',
        REF_ENTITY_NAME   => 'NEXUS_APP.CORE.CUSTOMERS'
    )
)

UNION ALL

SELECT
    measurement_time,
    table_schema,
    table_name,
    metric_name,
    column_name,
    value,
    CASE
        WHEN metric_name = 'DMF_NULL_COUNT'       AND value > 0   THEN 'WARN'
        WHEN metric_name = 'DMF_DUPLICATE_COUNT'  AND value > 0   THEN 'FAIL'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 24  THEN 'WARN'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 48  THEN 'FAIL'
        ELSE 'OK'
    END
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE',
        REF_ENTITY_NAME   => 'NEXUS_APP.CORE.TRANSACTIONS'
    )
)

UNION ALL

SELECT
    measurement_time,
    table_schema,
    table_name,
    metric_name,
    column_name,
    value,
    CASE
        WHEN metric_name = 'DMF_NULL_COUNT'       AND value > 0   THEN 'WARN'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 24  THEN 'WARN'
        WHEN metric_name = 'DMF_FRESHNESS_HOURS'  AND value > 48  THEN 'FAIL'
        ELSE 'OK'
    END
FROM TABLE(
    INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_DOMAIN => 'TABLE',
        REF_ENTITY_NAME   => 'NEXUS_APP.CORE.TICKETS'
    )
);

GRANT SELECT ON VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD TO ROLE NEXUS_ANALYST;
GRANT SELECT ON VIEW GOVERNANCE.V_DATA_QUALITY_DASHBOARD TO ROLE NEXUS_ADMIN;
