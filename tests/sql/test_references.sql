-- NEXUS AI DataOps — Acceptance Tests: References & Multi-tenancy
-- Sprint 2 — AT-101: references registradas corretamente
-- AT-102: RAP_ORG_ISOLATION isola orgs distintos
-- Executar como NEXUS_ADMIN após install do Native App

USE DATABASE NEXUS_APP;

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-101: CONFIG.DATA_SOURCES criada e inicializada
-- ─────────────────────────────────────────────────────────────────────────────

-- T101.1 — tabela DATA_SOURCES existe
SELECT 'T101.1' AS test_id, 'PASS' AS result
WHERE EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'CONFIG' AND TABLE_NAME = 'DATA_SOURCES'
)
UNION ALL
SELECT 'T101.1', 'FAIL' WHERE NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'CONFIG' AND TABLE_NAME = 'DATA_SOURCES'
);

-- T101.2 — 3 referências seeded (customer_table, transactions_table, events_table)
SELECT 'T101.2' AS test_id,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL: found ' || COUNT(*)::VARCHAR END AS result
FROM CONFIG.DATA_SOURCES
WHERE ref_name IN ('customer_table', 'transactions_table', 'events_table');

-- T101.3 — REGISTER_REFERENCE stored procedure existe
SELECT 'T101.3' AS test_id, 'PASS' AS result
WHERE EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.PROCEDURES
    WHERE PROCEDURE_SCHEMA = 'CORE' AND PROCEDURE_NAME = 'REGISTER_REFERENCE'
)
UNION ALL
SELECT 'T101.3', 'FAIL' WHERE NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.PROCEDURES
    WHERE PROCEDURE_SCHEMA = 'CORE' AND PROCEDURE_NAME = 'REGISTER_REFERENCE'
);

-- T101.4 — CONFIG.ORG_USER_MAP tem coluna role
SELECT 'T101.4' AS test_id, 'PASS' AS result
WHERE EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CONFIG' AND TABLE_NAME = 'ORG_USER_MAP' AND COLUMN_NAME = 'ROLE'
)
UNION ALL
SELECT 'T101.4', 'FAIL' WHERE NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'CONFIG' AND TABLE_NAME = 'ORG_USER_MAP' AND COLUMN_NAME = 'ROLE'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-102: Row Access Policy isola org_id
-- ─────────────────────────────────────────────────────────────────────────────

-- T102.1 — RAP_ORG_ISOLATION existe no schema CORE
SELECT 'T102.1' AS test_id, 'PASS' AS result
WHERE EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.ROW_ACCESS_POLICIES
    WHERE POLICY_SCHEMA = 'CORE' AND POLICY_NAME = 'RAP_ORG_ISOLATION'
)
UNION ALL
SELECT 'T102.1', 'FAIL' WHERE NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.ROW_ACCESS_POLICIES
    WHERE POLICY_SCHEMA = 'CORE' AND POLICY_NAME = 'RAP_ORG_ISOLATION'
);

-- T102.2 — RAP aplicada nas 8 tabelas esperadas
SELECT 'T102.2' AS test_id,
    CASE WHEN COUNT(DISTINCT ref_entity_name) >= 8 THEN 'PASS'
         ELSE 'FAIL: RAP em apenas ' || COUNT(DISTINCT ref_entity_name)::VARCHAR || ' tabelas'
    END AS result
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    POLICY_NAME => 'NEXUS_APP.CORE.RAP_ORG_ISOLATION'
));

-- T102.3 — Usuário de teste demo_org1 só vê clientes do org_id=demo_org1
-- (requer que NEXUS_ANALYST esteja mapeado para demo_org1 em ORG_USER_MAP)
-- Execute com: GRANT APPLICATION ROLE NEXUS_ANALYST TO USER <test_user>;
-- e verifique que SELECT COUNT(*) FROM CORE.CUSTOMERS retorna apenas registros de demo_org1
SELECT 'T102.3' AS test_id,
    'MANUAL: Execute como usuário demo_org1 e valide contagem = dados do org correto' AS result;

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-103: Canonical tables existem e têm estrutura correta
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'T103.1' AS test_id,
    CASE WHEN COUNT(*) = 3 THEN 'PASS'
         ELSE 'FAIL: ' || COUNT(*)::VARCHAR || '/3 canonical tables existem'
    END AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORE' AND TABLE_NAME IN ('ACCOUNTS', 'PRODUCTS', 'INTERACTIONS');

SELECT 'T103.2' AS test_id,
    CASE WHEN COUNT(*) >= 2 THEN 'PASS'
         ELSE 'FAIL: Dynamic Tables insuficientes'
    END AS result
FROM INFORMATION_SCHEMA.DYNAMIC_TABLES
WHERE TABLE_SCHEMA = 'MART';

-- ─────────────────────────────────────────────────────────────────────────────
-- Sumário
-- ─────────────────────────────────────────────────────────────────────────────
-- Resultado esperado: todas as linhas com result = 'PASS'
-- Em caso de FAIL, verificar setup_script.sql e re-executar REGISTER VERSION
