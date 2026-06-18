-- =============================================================================
-- NEXUS AI DataOps — Multi-Tenant Provider Analytics
-- Painel do provider: uso por consumer, créditos Snowflake, adoção por tenant.
-- Visível apenas para a conta provider (o distribuidor do Native App).
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA CORE;

-- ─── Schema de analytics do provider ────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.PROVIDER_ANALYTICS
    COMMENT = 'Multi-tenant usage analytics visible only to NEXUS provider account';


-- ─── Tabela: snapshot de uso por tenant ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS PROVIDER_ANALYTICS.TENANT_USAGE_SNAPSHOTS (
    snapshot_id         VARCHAR(36)     DEFAULT UUID_STRING() NOT NULL,
    org_id              VARCHAR(50)     NOT NULL,
    snapshot_date       DATE            DEFAULT CURRENT_DATE() NOT NULL,
    -- Streamlit
    streamlit_sessions  INTEGER         DEFAULT 0,
    streamlit_dau       INTEGER         DEFAULT 0,
    -- AI Usage
    cortex_calls        INTEGER         DEFAULT 0,
    cortex_tokens       BIGINT          DEFAULT 0,
    agent_sessions      INTEGER         DEFAULT 0,
    doc_searches        INTEGER         DEFAULT 0,
    -- Data
    documents_indexed   INTEGER         DEFAULT 0,
    recommendations_generated INTEGER   DEFAULT 0,
    actions_executed    INTEGER         DEFAULT 0,
    -- Compute
    warehouse_credits   NUMBER(10,4)    DEFAULT 0,
    -- Features adopted (bitmask via array)
    features_used       VARIANT,        -- ARRAY of feature names used this day
    PRIMARY KEY (snapshot_id),
    UNIQUE (org_id, snapshot_date)
);


-- ─── SP: Coletar snapshot diário de uso por tenant ───────────────────────────

CREATE OR REPLACE PROCEDURE PROVIDER_ANALYTICS.SP_COLLECT_USAGE_SNAPSHOT()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_date DATE;
    v_count INTEGER;
BEGIN
    v_date := CURRENT_DATE();

    MERGE INTO PROVIDER_ANALYTICS.TENANT_USAGE_SNAPSHOTS tgt
    USING (
        SELECT
            o.org_id,

            -- Sessões Streamlit (proxy via audit_log)
            COUNT_IF(al.resource_type = 'STREAMLIT_SESSION'
                AND al.created_at::DATE = :v_date)             AS streamlit_sessions,

            -- DAU (usuários únicos)
            COUNT(DISTINCT CASE
                WHEN al.created_at::DATE = :v_date THEN al.user_name END) AS streamlit_dau,

            -- Cortex AI
            COUNT_IF(al.resource_type = 'CORTEX_CALL'
                AND al.created_at::DATE = :v_date)             AS cortex_calls,

            -- Tokens (do API cost RT)
            COALESCE((
                SELECT SUM(total_tokens)
                FROM NEXUS_APP.MART.API_COST_RT
                WHERE org_id = o.org_id AND usage_date = :v_date
            ), 0)                                              AS cortex_tokens,

            -- Sessões de agente
            COALESCE((
                SELECT COUNT(*)
                FROM NEXUS_APP.AI.AGENT_SESSIONS
                WHERE org_id = o.org_id
                  AND started_at::DATE = :v_date
            ), 0)                                              AS agent_sessions,

            -- Documentos
            COALESCE((
                SELECT COUNT(*)
                FROM NEXUS_APP.CORE.DOCUMENTS
                WHERE org_id = o.org_id
                  AND processing_status = 'completed'
            ), 0)                                              AS documents_indexed,

            -- Recomendações
            COALESCE((
                SELECT COUNT(*)
                FROM NEXUS_APP.AI.RECOMMENDATIONS
                WHERE org_id = o.org_id
                  AND created_at::DATE = :v_date
            ), 0)                                              AS recommendations_generated,

            -- Ações executadas
            COALESCE((
                SELECT COUNT(*)
                FROM NEXUS_APP.AI.RECOMMENDATIONS
                WHERE org_id = o.org_id
                  AND status = 'accepted'
                  AND acted_at::DATE = :v_date
            ), 0)                                              AS actions_executed,

            -- Features usadas hoje
            ARRAY_COMPACT(ARRAY_CONSTRUCT(
                CASE WHEN COUNT_IF(al.resource_type = 'CORTEX_CALL' AND al.created_at::DATE = :v_date) > 0
                     THEN 'ai_chat' ELSE NULL END,
                CASE WHEN COUNT_IF(al.resource_type = 'DOC_SEARCH' AND al.created_at::DATE = :v_date) > 0
                     THEN 'document_search' ELSE NULL END,
                CASE WHEN COUNT_IF(al.resource_type = 'AGENT_SESSION' AND al.created_at::DATE = :v_date) > 0
                     THEN 'cortex_agents' ELSE NULL END
            ))                                                 AS features_used

        FROM (SELECT DISTINCT org_id FROM NEXUS_APP.CORE.CUSTOMERS) o
        LEFT JOIN NEXUS_APP.AUDIT.ACCESS_LOG al
               ON al.org_id = o.org_id
              AND al.created_at >= DATEADD('day', -1, CURRENT_TIMESTAMP())
        GROUP BY o.org_id
    ) src
    ON tgt.org_id = src.org_id AND tgt.snapshot_date = :v_date
    WHEN MATCHED THEN UPDATE SET
        streamlit_sessions        = src.streamlit_sessions,
        streamlit_dau             = src.streamlit_dau,
        cortex_calls              = src.cortex_calls,
        cortex_tokens             = src.cortex_tokens,
        agent_sessions            = src.agent_sessions,
        documents_indexed         = src.documents_indexed,
        recommendations_generated = src.recommendations_generated,
        actions_executed          = src.actions_executed,
        features_used             = src.features_used
    WHEN NOT MATCHED THEN INSERT
        (org_id, snapshot_date, streamlit_sessions, streamlit_dau,
         cortex_calls, cortex_tokens, agent_sessions, documents_indexed,
         recommendations_generated, actions_executed, features_used)
    VALUES
        (src.org_id, :v_date, src.streamlit_sessions, src.streamlit_dau,
         src.cortex_calls, src.cortex_tokens, src.agent_sessions,
         src.documents_indexed, src.recommendations_generated,
         src.actions_executed, src.features_used);

    SELECT COUNT(*) INTO v_count
    FROM PROVIDER_ANALYTICS.TENANT_USAGE_SNAPSHOTS
    WHERE snapshot_date = :v_date;

    RETURN 'Collected snapshots for ' || v_count::VARCHAR || ' tenants.';
END;
$$;


-- ─── View: painel do provider — uso atual por tenant ─────────────────────────

CREATE OR REPLACE VIEW PROVIDER_ANALYTICS.V_TENANT_HEALTH_DASHBOARD AS
WITH latest AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY org_id ORDER BY snapshot_date DESC) AS rn
    FROM PROVIDER_ANALYTICS.TENANT_USAGE_SNAPSHOTS
),
trend AS (
    SELECT org_id,
           AVG(streamlit_dau)   AS avg_dau_7d,
           AVG(cortex_calls)    AS avg_ai_calls_7d,
           AVG(agent_sessions)  AS avg_agent_sessions_7d
    FROM PROVIDER_ANALYTICS.TENANT_USAGE_SNAPSHOTS
    WHERE snapshot_date >= DATEADD('day', -7, CURRENT_DATE())
    GROUP BY org_id
)
SELECT
    l.org_id,
    l.snapshot_date                                         AS last_active,
    l.streamlit_dau,
    l.cortex_calls,
    l.cortex_tokens,
    l.agent_sessions,
    l.documents_indexed,
    l.actions_executed,
    l.features_used,
    ROUND(t.avg_dau_7d, 1)                                 AS avg_dau_7d,
    ROUND(t.avg_ai_calls_7d, 0)                            AS avg_ai_calls_7d,
    CASE
        WHEN t.avg_dau_7d >= 5 AND t.avg_ai_calls_7d >= 20 THEN 'HIGHLY_ENGAGED'
        WHEN t.avg_dau_7d >= 2 AND t.avg_ai_calls_7d >= 5  THEN 'ENGAGED'
        WHEN t.avg_dau_7d >= 1                              THEN 'CASUAL'
        ELSE 'AT_RISK_OF_CHURN'
    END                                                    AS engagement_tier,
    ARRAY_SIZE(l.features_used)                            AS features_adopted
FROM latest l
LEFT JOIN trend t ON l.org_id = t.org_id
WHERE l.rn = 1
ORDER BY l.cortex_calls DESC NULLS LAST;


-- ─── Task: snapshot diário às 23:45 UTC ──────────────────────────────────────

CREATE OR REPLACE TASK PROVIDER_ANALYTICS.TASK_DAILY_USAGE_SNAPSHOT
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 45 23 * * * UTC'
    COMMENT   = 'Collect daily usage snapshots for all tenants'
AS
CALL PROVIDER_ANALYTICS.SP_COLLECT_USAGE_SNAPSHOT();

ALTER TASK PROVIDER_ANALYTICS.TASK_DAILY_USAGE_SNAPSHOT RESUME;
