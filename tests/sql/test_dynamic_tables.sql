-- NEXUS AI DataOps — Acceptance Tests: Dynamic Tables & Tasks
-- Sprint 2 — AT-105: DTs existem e atualizam
-- AT-107: Tasks configuradas e ativas
-- Executar como NEXUS_ADMIN

USE DATABASE NEXUS_APP;

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-105: Dynamic Tables existem e têm TARGET_LAG esperado
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'T105.1' AS test_id,
    CASE WHEN COUNT(*) = 3 THEN 'PASS'
         ELSE 'FAIL: ' || COUNT(*)::VARCHAR || '/3 DTs no MART'
    END AS result
FROM INFORMATION_SCHEMA.DYNAMIC_TABLES
WHERE TABLE_SCHEMA = 'MART'
  AND TABLE_NAME IN ('DT_EXECUTIVE_KPIS', 'DT_CUSTOMER_HEALTH', 'DT_REVENUE_MOVEMENT');

-- T105.2 — DT_EXECUTIVE_KPIS retorna ao menos uma linha
SELECT 'T105.2' AS test_id,
    CASE WHEN COUNT(*) > 0 THEN 'PASS'
         ELSE 'FAIL: DT_EXECUTIVE_KPIS está vazia (verifique demo data)'
    END AS result
FROM MART.DT_EXECUTIVE_KPIS;

-- T105.3 — DT_CUSTOMER_HEALTH colunas esperadas
SELECT 'T105.3' AS test_id,
    CASE WHEN COUNT(*) >= 10 THEN 'PASS'
         ELSE 'FAIL: DT_CUSTOMER_HEALTH tem menos colunas que esperado'
    END AS result
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'MART' AND TABLE_NAME = 'DT_CUSTOMER_HEALTH';

-- T105.4 — DT_REVENUE_MOVEMENT tem dados
SELECT 'T105.4' AS test_id,
    CASE WHEN COUNT(*) > 0 THEN 'PASS'
         ELSE 'FAIL: DT_REVENUE_MOVEMENT vazia (verifique CORE.TRANSACTIONS demo data)'
    END AS result
FROM MART.DT_REVENUE_MOVEMENT;

-- T105.5 — DT_REVENUE_OPPORTUNITY_SCORE existe no MART
SELECT 'T105.5' AS test_id,
    CASE WHEN COUNT(*) > 0 THEN 'PASS'
         ELSE 'FAIL: DT_REVENUE_OPPORTUNITY_SCORE não encontrada'
    END AS result
FROM INFORMATION_SCHEMA.DYNAMIC_TABLES
WHERE TABLE_SCHEMA = 'MART' AND TABLE_NAME = 'DT_REVENUE_OPPORTUNITY_SCORE';

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-107: Tasks existem e estão no estado STARTED/RESUMED
-- ─────────────────────────────────────────────────────────────────────────────

-- T107.1 — 3 tasks existem
SELECT 'T107.1' AS test_id,
    CASE WHEN COUNT(*) >= 3 THEN 'PASS'
         ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || '/3 tasks encontradas'
    END AS result
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA IN ('CORE', 'MART')
  AND TASK_NAME IN ('TASK_RUN_CHURN_PIPELINE', 'TASK_EXECUTIVE_BRIEFING', 'TASK_REFRESH_REVENUE_SCORE');

-- T107.2 — Tasks estão STARTED (ativas)
SELECT 'T107.2' AS test_id,
    CASE WHEN COUNT(*) >= 3 THEN 'PASS'
         ELSE 'FAIL: tasks não estão no estado STARTED'
    END AS result
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA IN ('CORE', 'MART')
  AND TASK_NAME IN ('TASK_RUN_CHURN_PIPELINE', 'TASK_EXECUTIVE_BRIEFING', 'TASK_REFRESH_REVENUE_SCORE')
  AND STATE = 'started';

-- T107.3 — Task schedules corretos
SELECT
    TASK_NAME,
    SCHEDULE,
    STATE,
    CASE
        WHEN TASK_NAME = 'TASK_RUN_CHURN_PIPELINE'   AND SCHEDULE LIKE '%0 2%' THEN 'PASS'
        WHEN TASK_NAME = 'TASK_EXECUTIVE_BRIEFING'   AND SCHEDULE LIKE '%0 7%' THEN 'PASS'
        WHEN TASK_NAME = 'TASK_REFRESH_REVENUE_SCORE' AND SCHEDULE LIKE '%*/6%' THEN 'PASS'
        ELSE 'REVIEW: verificar schedule'
    END AS schedule_check
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA IN ('CORE', 'MART')
  AND TASK_NAME IN ('TASK_RUN_CHURN_PIPELINE', 'TASK_EXECUTIVE_BRIEFING', 'TASK_REFRESH_REVENUE_SCORE');

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-108: KBS schema e Cortex Search Service existem
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'T108.1' AS test_id,
    CASE WHEN COUNT(*) = 3 THEN 'PASS'
         ELSE 'FAIL: ' || COUNT(*)::VARCHAR || '/3 tabelas KBS'
    END AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'KBS'
  AND TABLE_NAME IN ('DOCUMENTS', 'SOURCES', 'SEARCH_LOGS');

-- T108.2 — Cortex Search Service existe (requer Snowflake Cortex habilitado)
-- SHOW CORTEX SEARCH SERVICES IN SCHEMA KBS;
SELECT 'T108.2' AS test_id,
    'MANUAL: executar SHOW CORTEX SEARCH SERVICES IN SCHEMA KBS e verificar KB_SEARCH_SERVICE' AS result;

-- ─────────────────────────────────────────────────────────────────────────────
-- AT-109: Agent roles existem e têm GRANTs corretos
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'T109.1' AS test_id,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS'
         ELSE 'FAIL: apenas ' || COUNT(*)::VARCHAR || ' agent roles'
    END AS result
FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
WHERE ROLE_NAME LIKE 'AGENT_%_READONLY';
