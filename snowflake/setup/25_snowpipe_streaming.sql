-- =============================================================================
-- NEXUS AI DataOps — Snowpipe Streaming
-- Ingestão em tempo real de eventos de produto via Snowpipe Streaming SDK.
-- Tabelas de landing (RAW), views de normalização e canais por tipo de evento.
-- =============================================================================

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE SCHEMA RAW;

-- ─── Schema RAW para dados de ingestão real-time ─────────────────────────────

CREATE SCHEMA IF NOT EXISTS NEXUS_APP.RAW
    COMMENT = 'Landing zone para Snowpipe Streaming — dados brutos antes da normalização';


-- ─── Tabelas de landing ───────────────────────────────────────────────────────

-- Eventos de produto (cliques, page views, feature usage)
CREATE TABLE IF NOT EXISTS RAW.PRODUCT_EVENTS (
    event_id        VARCHAR(64)     NOT NULL,
    org_id          VARCHAR(50)     NOT NULL,
    customer_id     VARCHAR(50),
    user_id         VARCHAR(100),
    session_id      VARCHAR(100),
    event_type      VARCHAR(100)    NOT NULL,  -- page_view|feature_used|api_call|error|login
    event_payload   VARIANT,
    client_ts       TIMESTAMP_TZ,
    server_ts       TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    ingested_at     TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    _metadata       VARIANT,
    PRIMARY KEY (event_id)
)
COMMENT = 'Raw product events via Snowpipe Streaming';

-- Métricas de uso de API por organização
CREATE TABLE IF NOT EXISTS RAW.API_USAGE_EVENTS (
    event_id        VARCHAR(64)     NOT NULL,
    org_id          VARCHAR(50)     NOT NULL,
    endpoint        VARCHAR(500)    NOT NULL,
    method          VARCHAR(10),
    status_code     INTEGER,
    latency_ms      INTEGER,
    tokens_used     INTEGER,
    model_name      VARCHAR(100),
    request_ts      TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    ingested_at     TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_id)
)
COMMENT = 'Raw API usage metrics via Snowpipe Streaming';

-- Eventos de saúde do sistema (health score updates)
CREATE TABLE IF NOT EXISTS RAW.HEALTH_SCORE_EVENTS (
    event_id        VARCHAR(64)     NOT NULL,
    org_id          VARCHAR(50)     NOT NULL,
    customer_id     VARCHAR(50)     NOT NULL,
    score_delta     NUMBER(5,2),
    new_score       NUMBER(5,2),
    score_driver    VARCHAR(200),
    event_ts        TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    ingested_at     TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (event_id)
)
COMMENT = 'Real-time health score change events';


-- ─── Canais Snowpipe Streaming ────────────────────────────────────────────────

CREATE OR REPLACE PIPE RAW.PIPE_PRODUCT_EVENTS
    AUTO_INGEST = FALSE
    COMMENT     = 'Snowpipe Streaming channel for product events (SDK insert)'
AS
COPY INTO RAW.PRODUCT_EVENTS
FROM (
    SELECT
        $1:event_id::VARCHAR,
        $1:org_id::VARCHAR,
        $1:customer_id::VARCHAR,
        $1:user_id::VARCHAR,
        $1:session_id::VARCHAR,
        $1:event_type::VARCHAR,
        $1:event_payload::VARIANT,
        TRY_TO_TIMESTAMP_TZ($1:client_ts::VARCHAR),
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP(),
        $1::VARIANT
    FROM @CORE.APP_STAGE/streaming/product_events/
)
FILE_FORMAT = (TYPE = 'JSON');


CREATE OR REPLACE PIPE RAW.PIPE_API_USAGE
    AUTO_INGEST = FALSE
    COMMENT     = 'Snowpipe Streaming channel for API usage metrics'
AS
COPY INTO RAW.API_USAGE_EVENTS
FROM (
    SELECT
        $1:event_id::VARCHAR,
        $1:org_id::VARCHAR,
        $1:endpoint::VARCHAR,
        $1:method::VARCHAR,
        $1:status_code::INTEGER,
        $1:latency_ms::INTEGER,
        $1:tokens_used::INTEGER,
        $1:model_name::VARCHAR,
        TRY_TO_TIMESTAMP_TZ($1:request_ts::VARCHAR),
        CURRENT_TIMESTAMP()
    FROM @CORE.APP_STAGE/streaming/api_usage/
)
FILE_FORMAT = (TYPE = 'JSON');


-- ─── Dynamic Table: feature usage por cliente (1h lag) ───────────────────────

CREATE OR REPLACE DYNAMIC TABLE MART.FEATURE_USAGE_RT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Feature adoption and engagement — refreshed hourly from Snowpipe Streaming'
AS
SELECT
    org_id,
    customer_id,
    DATE_TRUNC('hour', server_ts)               AS event_hour,
    event_type,
    COUNT(*)                                     AS event_count,
    COUNT(DISTINCT user_id)                      AS unique_users,
    COUNT(DISTINCT session_id)                   AS unique_sessions,
    MAX(server_ts)                               AS last_seen
FROM RAW.PRODUCT_EVENTS
WHERE server_ts >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3, 4;


-- ─── Dynamic Table: API cost tracking (2h lag) ───────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE MART.API_COST_RT
    TARGET_LAG = '2 hours'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'LLM token consumption and API cost aggregates — refreshed every 2h'
AS
SELECT
    org_id,
    DATE_TRUNC('day', request_ts)               AS usage_date,
    model_name,
    COUNT(*)                                     AS api_calls,
    SUM(tokens_used)                             AS total_tokens,
    SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS error_count,
    ROUND(AVG(latency_ms), 0)                   AS avg_latency_ms,
    ROUND(SUM(tokens_used) * 0.000003, 4)       AS estimated_cost_usd
FROM RAW.API_USAGE_EVENTS
WHERE request_ts >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3;


-- ─── Grants para o canal de streaming ────────────────────────────────────────

GRANT INSERT, SELECT ON TABLE RAW.PRODUCT_EVENTS   TO ROLE NEXUS_PIPELINE_ROLE;
GRANT INSERT, SELECT ON TABLE RAW.API_USAGE_EVENTS TO ROLE NEXUS_PIPELINE_ROLE;
GRANT INSERT, SELECT ON TABLE RAW.HEALTH_SCORE_EVENTS TO ROLE NEXUS_PIPELINE_ROLE;
GRANT OPERATE ON PIPE RAW.PIPE_PRODUCT_EVENTS TO ROLE NEXUS_PIPELINE_ROLE;
GRANT OPERATE ON PIPE RAW.PIPE_API_USAGE      TO ROLE NEXUS_PIPELINE_ROLE;
