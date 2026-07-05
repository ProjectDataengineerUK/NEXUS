-- NEXUS AI DataOps — Knowledge Base System (KBS) schema standalone
-- Sprint 2 — P1: executar fora do Native App (ou referenciar no setup_script)
-- O equivalente já está no setup_script.sql via bloco "P1 KBS"

USE DATABASE NEXUS_APP;
CREATE SCHEMA IF NOT EXISTS KBS;

CREATE TABLE IF NOT EXISTS KBS.SOURCES (
    source_id    VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    kb_name      VARCHAR(100)  NOT NULL,
    source_type  VARCHAR(50)   CHECK (source_type IN ('snowflake_docs', 'cortex_docs', 'internal_wiki', 'api_docs', 'custom')),
    source_url   VARCHAR(2000),
    is_active    BOOLEAN       DEFAULT TRUE,
    last_loaded  TIMESTAMP_TZ,
    created_at   TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_kbs_sources PRIMARY KEY (source_id)
);

CREATE TABLE IF NOT EXISTS KBS.DOCUMENTS (
    doc_id       VARCHAR(36)   NOT NULL DEFAULT UUID_STRING(),
    source_id    VARCHAR(36)   NOT NULL,
    kb_name      VARCHAR(100)  NOT NULL,
    title        VARCHAR(1000),
    content      TEXT          NOT NULL,
    chunk_index  INTEGER       DEFAULT 0,
    url          VARCHAR(2000),
    doc_metadata VARIANT,
    created_at   TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at   TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_kbs_documents PRIMARY KEY (doc_id),
    CONSTRAINT fk_kbs_documents_source FOREIGN KEY (source_id) REFERENCES KBS.SOURCES(source_id)
);

CREATE TABLE IF NOT EXISTS KBS.SEARCH_LOGS (
    log_id        VARCHAR(36)  NOT NULL DEFAULT UUID_STRING(),
    org_id        VARCHAR(50),
    kb_name       VARCHAR(100),
    query_text    TEXT,
    results_count INTEGER,
    latency_ms    INTEGER,
    model_used    VARCHAR(100),
    searched_at   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_kbs_search_logs PRIMARY KEY (log_id)
);

GRANT USAGE  ON SCHEMA         KBS                         TO ROLE NEXUS_VIEWER;
GRANT SELECT ON ALL TABLES IN SCHEMA KBS                   TO ROLE NEXUS_VIEWER;
GRANT INSERT ON TABLE KBS.SEARCH_LOGS                      TO ROLE NEXUS_ANALYST;
GRANT INSERT, UPDATE ON TABLE KBS.DOCUMENTS                TO ROLE NEXUS_ADMIN;
GRANT INSERT, UPDATE ON TABLE KBS.SOURCES                  TO ROLE NEXUS_ADMIN;

INSERT INTO KBS.SOURCES (kb_name, source_type, source_url, is_active)
SELECT kb_name, source_type, source_url, TRUE
FROM (
    VALUES
    ('snowflake_core',  'snowflake_docs', 'https://docs.snowflake.com', TRUE),
    ('cortex_ai',       'cortex_docs',    'https://docs.snowflake.com/en/guides-overview-ai-features', TRUE),
    ('nexus_platform',  'internal_wiki',  'internal://nexus-platform-docs', TRUE)
) v(kb_name, source_type, source_url, is_active)
WHERE NOT EXISTS (SELECT 1 FROM KBS.SOURCES s WHERE s.kb_name = v.kb_name);
