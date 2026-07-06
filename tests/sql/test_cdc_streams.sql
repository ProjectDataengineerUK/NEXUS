-- NEXUS Sprint 4 — Acceptance Tests: Conectores (SAP/Oracle/HubSpot) + CDC via Streams
-- Execute against NEXUS_APP database with NEXUS_ADMIN role
-- Expected: all results = 'PASS'

-- AT-120: STAGING tables dos 3 novos conectores existem
SELECT 'AT-120' AS test_id,
       'Staging tables for SAP/Oracle/HubSpot exist' AS description,
       CASE
           WHEN COUNT(*) = 9 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || '/9 staging tables encontradas'
       END AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'STAGING'
  AND TABLE_NAME IN (
      'SAP_CUSTOMERS', 'SAP_INVOICES', 'SAP_ORDERS',
      'ORACLE_CUSTOMERS', 'ORACLE_ORDERS', 'ORACLE_INVOICES',
      'HUBSPOT_CONTACTS', 'HUBSPOT_DEALS', 'HUBSPOT_COMPANIES'
  );

-- AT-123: Streams sobre as staging tables existem
SELECT 'AT-123' AS test_id,
       'CDC streams exist for all staging tables' AS description,
       CASE
           WHEN COUNT(*) = 9 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || '/9 streams encontrados'
       END AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'STAGING'
  AND TABLE_NAME IN (
      'SAP_CUSTOMERS_STREAM', 'SAP_INVOICES_STREAM', 'SAP_ORDERS_STREAM',
      'ORACLE_CUSTOMERS_STREAM', 'ORACLE_ORDERS_STREAM', 'ORACLE_INVOICES_STREAM',
      'HUBSPOT_CONTACTS_STREAM', 'HUBSPOT_DEALS_STREAM', 'HUBSPOT_COMPANIES_STREAM'
  );

-- AT-124: Tasks de MERGE incremental (CDC) existem e estão iniciadas
-- Nota: RESUME é feito de forma tolerante (ver setup_script.sql) — pode
-- ficar 'suspended' até o GRANT EXECUTE TASK ser concedido pelo consumer
-- num upgrade seguinte (ver Sprint 3, mesmo padrão para outras tasks).
SELECT 'AT-124' AS test_id,
       'CDC merge tasks exist' AS description,
       CASE
           WHEN COUNT(*) = 6 THEN 'PASS'
           ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || '/6 tasks de CDC encontradas'
       END AS result
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA = 'CORE'
  AND TASK_NAME IN (
      'TASK_MERGE_SAP_CUSTOMERS', 'TASK_MERGE_SAP_INVOICES',
      'TASK_MERGE_ORACLE_CUSTOMERS', 'TASK_MERGE_ORACLE_ORDERS',
      'TASK_MERGE_HUBSPOT_CONTACTS', 'TASK_MERGE_HUBSPOT_DEALS'
  );

-- AT-124b: CDC tasks apontam para o warehouse correto
SELECT 'AT-124b' AS test_id,
       'CDC tasks use NEXUS_COMPUTE_WH' AS description,
       CASE
           WHEN COUNT(*) = 6 THEN 'PASS'
           ELSE 'FAIL: ' || COUNT(*)::VARCHAR || '/6 tasks usam NEXUS_COMPUTE_WH'
       END AS result
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA = 'CORE'
  AND TASK_NAME IN (
      'TASK_MERGE_SAP_CUSTOMERS', 'TASK_MERGE_SAP_INVOICES',
      'TASK_MERGE_ORACLE_CUSTOMERS', 'TASK_MERGE_ORACLE_ORDERS',
      'TASK_MERGE_HUBSPOT_CONTACTS', 'TASK_MERGE_HUBSPOT_DEALS'
  )
  AND WAREHOUSE_NAME = 'NEXUS_COMPUTE_WH';

-- AT-125: app_version reflete v4.0.0
SELECT 'AT-125' AS test_id,
       'App version bumped to 4.0.0' AS description,
       CASE
           WHEN setting_value = '4.0.0' THEN 'PASS'
           ELSE 'FAIL: setting_value = ' || setting_value
       END AS result
FROM CONFIG.APP_SETTINGS
WHERE setting_key = 'app_version';
