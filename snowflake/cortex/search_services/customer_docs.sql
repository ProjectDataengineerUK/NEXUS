-- Cortex Search Service — Document chunks for semantic search
-- Used by: AI Chat (Executive Agent) and Document Intelligence pages
-- Service name: AI.DOC_SEARCH   Refresh: 1 hour

CREATE OR REPLACE CORTEX SEARCH SERVICE AI.DOC_SEARCH
    ON chunk_text
    ATTRIBUTES org_id, document_id, document_name, document_type
    WAREHOUSE = NEXUS_COMPUTE_WH
    TARGET_LAG = '1 hour'
    COMMENT = 'Semantic search sobre chunks de documentos NEXUS — contratos, relatórios, manuais'
AS (
    SELECT
        chunk_id,
        org_id,
        document_id,
        document_name,
        document_type,
        chunk_text,
        chunk_index,
        COALESCE(section_title, '') AS section_title
    FROM AI.DOCUMENT_CHUNKS
    WHERE processing_status IS NULL OR processing_status = 'indexed'
);

GRANT USAGE ON CORTEX SEARCH SERVICE AI.DOC_SEARCH TO APPLICATION ROLE NEXUS_ADMIN_ROLE;
GRANT USAGE ON CORTEX SEARCH SERVICE AI.DOC_SEARCH TO APPLICATION ROLE NEXUS_USER_ROLE;
