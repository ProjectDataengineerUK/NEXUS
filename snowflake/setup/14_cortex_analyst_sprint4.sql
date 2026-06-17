-- NEXUS AI DataOps — Sprint 4: Cortex Analyst + Executive Agent
-- Stage para semantic models, upload do YAML, grants de Cortex

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stage para semantic models (Cortex Analyst)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS NEXUS_APP.CORE.SEMANTIC_STAGE
    DIRECTORY         = (ENABLE = TRUE)
    ENCRYPTION        = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT           = 'Semantic models YAML para Cortex Analyst';

GRANT READ  ON STAGE NEXUS_APP.CORE.SEMANTIC_STAGE TO ROLE NEXUS_ADMIN;
GRANT WRITE ON STAGE NEXUS_APP.CORE.SEMANTIC_STAGE TO ROLE NEXUS_ADMIN;
GRANT READ  ON STAGE NEXUS_APP.CORE.SEMANTIC_STAGE TO ROLE NEXUS_ANALYST;
GRANT READ  ON STAGE NEXUS_APP.CORE.SEMANTIC_STAGE TO ROLE NEXUS_VIEWER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Upload do semantic model via SnowSQL / CLI (executar localmente):
--
--   snowsql -c nexus_prod -q "PUT file://snowflake/cortex/semantic_models/nexus_revenue.yaml
--       @NEXUS_APP.CORE.SEMANTIC_STAGE/
--       AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
--
-- Ou via Python SDK:
--   session.file.put("snowflake/cortex/semantic_models/nexus_revenue.yaml",
--                    "@NEXUS_APP.CORE.SEMANTIC_STAGE/", overwrite=True)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela de histórico de queries do Cortex Analyst (analytics de uso)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.CORTEX_ANALYST_LOG (
    query_id        VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id          VARCHAR(36)  NOT NULL,
    user_name       VARCHAR(255) NOT NULL,
    user_role       VARCHAR(255),
    question        TEXT         NOT NULL,
    generated_sql   TEXT,
    model_used      VARCHAR(100),
    tokens_used     INTEGER,
    latency_ms      INTEGER,
    was_helpful     BOOLEAN,
    session_id      VARCHAR(36),
    created_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (query_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela de histórico de sessões do Executive Agent
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS NEXUS_APP.AUDIT.AGENT_CHAT_LOG (
    message_id      VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    session_id      VARCHAR(36)  NOT NULL,
    org_id          VARCHAR(36)  NOT NULL,
    user_name       VARCHAR(255) NOT NULL,
    role            VARCHAR(20)  NOT NULL,   -- user | assistant | tool
    content         TEXT         NOT NULL,
    tool_name       VARCHAR(100),
    tool_input      VARIANT,
    tool_output     TEXT,
    model_used      VARCHAR(100),
    latency_ms      INTEGER,
    created_at      TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (message_id)
);

GRANT INSERT ON TABLE NEXUS_APP.AUDIT.CORTEX_ANALYST_LOG TO ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE NEXUS_APP.AUDIT.AGENT_CHAT_LOG    TO ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE NEXUS_APP.AUDIT.CORTEX_ANALYST_LOG TO ROLE NEXUS_ANALYST;
GRANT SELECT ON TABLE NEXUS_APP.AUDIT.AGENT_CHAT_LOG    TO ROLE NEXUS_ANALYST;

-- ─────────────────────────────────────────────────────────────────────────────
-- Privilege para Cortex Analyst e Cortex Complete
-- (SNOWFLAKE.CORTEX_USER database role é necessária no account)
-- ─────────────────────────────────────────────────────────────────────────────

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE NEXUS_VIEWER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE NEXUS_ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE NEXUS_ADMIN;
