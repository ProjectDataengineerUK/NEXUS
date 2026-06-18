-- NEXUS AI DataOps — SQL Tests: Core Tables
-- Executar como: snowsql -f tests/sql/test_core_tables.sql
-- Cada assertion usa RESULT_SCAN + exceção para falhar ruidosamente.

USE DATABASE NEXUS_APP;
USE ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: lança exceção se condição falhar
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.ASSERT(
    condition  BOOLEAN,
    msg        VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, condition: bool, msg: str) -> str:
    if not condition:
        raise ValueError(f"ASSERTION FAILED: {msg}")
    return f"PASS: {msg}"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- T1: CORE.CUSTOMERS — PKs únicas, sem nulls obrigatórios
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.CUSTOMERS WHERE customer_id IS NULL) = 0,
    'CORE.CUSTOMERS.customer_id has no NULLs'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.CUSTOMERS WHERE org_id IS NULL) = 0,
    'CORE.CUSTOMERS.org_id has no NULLs'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM CORE.CUSTOMERS) = 0,
    'CORE.CUSTOMERS.customer_id is unique'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.CUSTOMERS
     WHERE lifecycle_stage NOT IN ('active', 'at_risk', 'churned', 'onboarding')) = 0,
    'CORE.CUSTOMERS.lifecycle_stage has only valid values'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T2: CORE.SUBSCRIPTIONS — valores de MRR não negativos
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.SUBSCRIPTIONS WHERE subscription_id IS NULL) = 0,
    'CORE.SUBSCRIPTIONS.subscription_id has no NULLs'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.SUBSCRIPTIONS WHERE mrr < 0) = 0,
    'CORE.SUBSCRIPTIONS.mrr >= 0'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T3: CORE.TICKETS — FKs válidas
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.TICKETS t
     LEFT JOIN CORE.CUSTOMERS c ON c.customer_id = t.customer_id
     WHERE c.customer_id IS NULL) = 0,
    'CORE.TICKETS.customer_id references valid CUSTOMERS'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM CORE.TICKETS
     WHERE priority NOT IN ('low', 'medium', 'high', 'critical', 'normal', 'urgent')) = 0,
    'CORE.TICKETS.priority has only valid values'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T4: AI tables — CHURN_SCORES em range válido
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM AI.CHURN_SCORES
     WHERE churn_probability < 0 OR churn_probability > 1) = 0,
    'AI.CHURN_SCORES.churn_probability in [0,1]'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM AI.CHURN_SCORES
     WHERE risk_level NOT IN ('HIGH', 'MEDIUM', 'LOW')) = 0,
    'AI.CHURN_SCORES.risk_level has only valid values'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T5: MART — EXECUTIVE_KPIS sem valores negativos em KPIs financeiros
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM MART.EXECUTIVE_KPIS WHERE total_arr < 0) = 0,
    'MART.EXECUTIVE_KPIS.total_arr >= 0'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM MART.EXECUTIVE_KPIS WHERE active_customers < 0) = 0,
    'MART.EXECUTIVE_KPIS.active_customers >= 0'
);

SELECT 'ALL CORE TABLE TESTS PASSED' AS status;
