-- NEXUS AI DataOps — Cortex Search Service para Knowledge Base
-- Sprint 2 — P1: serviço unificado com filtro por kb_name
-- Requer: Snowflake Cortex habilitado na conta, tabela KBS.DOCUMENTS populada

USE DATABASE NEXUS_APP;
USE SCHEMA KBS;

-- Cortex Search Service com coluna de filtro kb_name
-- Cada knowledge base é acessível via filtro { "kb_name": "snowflake_core" }
CREATE OR REPLACE CORTEX SEARCH SERVICE KBS.KB_SEARCH_SERVICE
    ON content
    ATTRIBUTES kb_name, title, url
    WAREHOUSE = NEXUS_COMPUTE_WH
    TARGET_LAG = '1 hour'
AS (
    SELECT
        doc_id,
        kb_name,
        title,
        content,
        url,
        chunk_index,
        created_at
    FROM KBS.DOCUMENTS
    WHERE LENGTH(content) > 50
);

GRANT USAGE ON CORTEX SEARCH SERVICE KBS.KB_SEARCH_SERVICE TO APPLICATION ROLE NEXUS_VIEWER;

-- Exemplo de uso via Snowflake Python (para referência):
-- from snowflake.core import Root
-- root = Root(session)
-- svc = root.databases["NEXUS_APP"].schemas["KBS"].cortex_search_services["KB_SEARCH_SERVICE"]
-- resp = svc.search(
--     query="como criar dynamic table no Snowflake",
--     columns=["title", "content", "url"],
--     filter={"@eq": {"kb_name": "snowflake_core"}},
--     limit=5
-- )
