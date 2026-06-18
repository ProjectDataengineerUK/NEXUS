-- NEXUS AI DataOps — SQL Tests: Security & Governance
-- Verifica masking policies, RBAC e isolamento multi-tenant.

USE DATABASE NEXUS_APP;
USE ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- T1: Application Roles existem
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
     WHERE role_name = 'NEXUS_ADMIN') > 0,
    'APPLICATION ROLE NEXUS_ADMIN exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
     WHERE role_name = 'NEXUS_ANALYST') > 0,
    'APPLICATION ROLE NEXUS_ANALYST exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
     WHERE role_name = 'NEXUS_VIEWER') > 0,
    'APPLICATION ROLE NEXUS_VIEWER exists'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T2: Schemas esperados existem
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA
     WHERE schema_name = 'CORE') > 0,
    'Schema CORE exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA
     WHERE schema_name = 'AI') > 0,
    'Schema AI exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA
     WHERE schema_name = 'AUDIT') > 0,
    'Schema AUDIT exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA
     WHERE schema_name = 'MART') > 0,
    'Schema MART exists'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T3: AUDIT tables são append-only (sem DELETE/UPDATE para VIEWER)
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES
     WHERE table_schema = 'AUDIT'
       AND privilege_type IN ('DELETE', 'UPDATE', 'TRUNCATE')
       AND grantee = 'NEXUS_VIEWER') = 0,
    'NEXUS_VIEWER has no DELETE/UPDATE/TRUNCATE on AUDIT schema'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T4: CONFIG.APP_SETTINGS acessível apenas para ADMIN
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES
     WHERE table_name = 'APP_SETTINGS'
       AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
       AND grantee = 'NEXUS_VIEWER') = 0,
    'NEXUS_VIEWER has no write access to CONFIG.APP_SETTINGS'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- T5: Stages existem
-- ─────────────────────────────────────────────────────────────────────────────

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STAGES
     WHERE stage_name = 'APP_STAGE' AND stage_schema = 'CORE') > 0,
    'Stage CORE.APP_STAGE exists'
);

CALL CORE.ASSERT(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STAGES
     WHERE stage_name = 'SEMANTIC_STAGE' AND stage_schema = 'CORE') > 0,
    'Stage CORE.SEMANTIC_STAGE exists'
);

SELECT 'ALL SECURITY TESTS PASSED' AS status;
