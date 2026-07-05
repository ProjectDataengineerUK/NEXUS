-- NEXUS Sprint 3 — Acceptance Tests: Semantic Models & Multi-org
-- Execute against NEXUS_APP database with NEXUS_ADMIN role
-- Expected: all results = 'PASS'

-- AT-110: CORE.SEMANTIC_STAGE existe
SELECT 'AT-110' AS test_id,
       'SEMANTIC_STAGE exists' AS description,
       CASE
           WHEN COUNT(*) >= 1 THEN 'PASS'
           ELSE 'FAIL: SEMANTIC_STAGE not found in CORE schema'
       END AS result
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'CORE'
  AND STAGE_NAME = 'SEMANTIC_STAGE';

-- AT-112: Demo data tem 2 org_ids distintos (ORG-DEMO-001 e ORG-DEMO-002)
SELECT 'AT-112' AS test_id,
       'Multi-org demo data' AS description,
       CASE
           WHEN COUNT(DISTINCT org_id) >= 2 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(DISTINCT org_id)::VARCHAR || ' org(s) no demo data'
       END AS result
FROM CORE.CUSTOMERS;

-- AT-112b: ORG-DEMO-002 tem pelo menos 3 clientes
SELECT 'AT-112b' AS test_id,
       'ORG-DEMO-002 has customers' AS description,
       CASE
           WHEN COUNT(*) >= 3 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || ' cliente(s) para ORG-DEMO-002'
       END AS result
FROM CORE.CUSTOMERS
WHERE org_id = 'ORG-DEMO-002';

-- AT-112c: ORG_USER_MAP tem entrada para ORG-DEMO-002
SELECT 'AT-112c' AS test_id,
       'ORG_USER_MAP has ORG-DEMO-002 entry' AS description,
       CASE
           WHEN COUNT(*) >= 1 THEN 'PASS'
           ELSE 'FAIL: nenhum usuário mapeado para ORG-DEMO-002'
       END AS result
FROM CONFIG.ORG_USER_MAP
WHERE org_id = 'ORG-DEMO-002';

-- AT-113: STAGING schema existe
SELECT 'AT-113' AS test_id,
       'STAGING schema exists' AS description,
       CASE
           WHEN COUNT(*) = 1 THEN 'PASS'
           ELSE 'FAIL: schema STAGING não encontrado'
       END AS result
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME = 'STAGING';

-- AT-113b: AI.AGENT_MEMORY table existe (P2)
SELECT 'AT-113b' AS test_id,
       'AI.AGENT_MEMORY table exists' AS description,
       CASE
           WHEN COUNT(*) = 1 THEN 'PASS'
           ELSE 'FAIL: tabela AI.AGENT_MEMORY não encontrada'
       END AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'AI'
  AND TABLE_NAME = 'AGENT_MEMORY';

-- AT-114: Semantic models no stage (verificar após upload_semantic_models.sh)
-- Requer execução manual após PUT — resultado esperado = 5 arquivos
SELECT 'AT-114' AS test_id,
       'Semantic models count in stage' AS description,
       CASE
           WHEN COUNT(*) >= 5 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || '/5 models no stage — execute upload_semantic_models.sh'
       END AS result
FROM (LIST @CORE.SEMANTIC_STAGE) stage_list
WHERE "name" LIKE '%.yaml';

-- AT-115: Tabelas de suporte dos novos modelos existem
SELECT 'AT-115a' AS test_id,
       'MART.REVENUE_OPPORTUNITY_SCORE accessible' AS description,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM MART.REVENUE_OPPORTUNITY_SCORE;

SELECT 'AT-115b' AS test_id,
       'MART.DT_REVENUE_MOVEMENT accessible' AS description,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM MART.DT_REVENUE_MOVEMENT;

SELECT 'AT-115c' AS test_id,
       'MART.DT_CUSTOMER_HEALTH accessible' AS description,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM MART.DT_CUSTOMER_HEALTH;

-- AT-115d: ORG-DEMO-002 tickets existem (isolação RAP)
SELECT 'AT-115d' AS test_id,
       'ORG-DEMO-002 tickets seeded' AS description,
       CASE
           WHEN COUNT(*) >= 3 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || ' ticket(s) para ORG-DEMO-002'
       END AS result
FROM CORE.TICKETS
WHERE org_id = 'ORG-DEMO-002';

-- AT-115e: ORG-DEMO-002 interactions existem
SELECT 'AT-115e' AS test_id,
       'ORG-DEMO-002 interactions seeded' AS description,
       CASE
           WHEN COUNT(*) >= 2 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || ' interação(ões) para ORG-DEMO-002'
       END AS result
FROM CORE.INTERACTIONS
WHERE org_id = 'ORG-DEMO-002';

-- AT-116: Versão do app atualizada para v3.0.0
SELECT 'AT-116' AS test_id,
       'App version is 3.0.0' AS description,
       CASE
           WHEN setting_value = '3.0.0' THEN 'PASS'
           ELSE 'FAIL: version = ' || COALESCE(setting_value, 'NULL')
       END AS result
FROM CONFIG.APP_SETTINGS
WHERE setting_key = 'app_version';
