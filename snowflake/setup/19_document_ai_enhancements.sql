-- NEXUS AI DataOps — Document AI Enhancements
-- AI_CLASSIFY + AI_SUMMARIZE para enriquecimento automático de documentos.

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Novas colunas na tabela CORE.DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS document_category VARCHAR(100);
ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS document_summary  TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: enriquecer documentos com CLASSIFY_TEXT e SUMMARIZE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, org_id):
    rows = session.sql(f"""
        SELECT document_id, extracted_text, document_type
        FROM CORE.DOCUMENTS
        WHERE org_id = '{org_id}'
          AND extracted_text IS NOT NULL
          AND (document_category IS NULL OR document_summary IS NULL)
        LIMIT 50
    """).collect()

    updated = 0
    for r in rows:
        text   = (r['EXTRACTED_TEXT'] or '')[:2000].replace("'", "''")
        doc_id = r['DOCUMENT_ID']

        result = session.sql(f"""
            SELECT
                SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
                    '{text}',
                    ARRAY_CONSTRUCT('contract', 'invoice', 'support_ticket', 'policy', 'report', 'other')
                ):label::VARCHAR AS category,
                SNOWFLAKE.CORTEX.SUMMARIZE('{text}') AS summary
        """).collect()

        if result:
            cat  = (result[0]['CATEGORY'] or 'other').replace("'", "''")
            summ = (result[0]['SUMMARY']  or '').replace("'", "''")
            session.sql(f"""
                UPDATE CORE.DOCUMENTS
                SET document_category = '{cat}',
                    document_summary  = '{summ}'
                WHERE document_id = '{doc_id}'
            """).collect()
            updated += 1

    return f"OK: {updated} documents enriched"
$$;

GRANT USAGE ON PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(VARCHAR)
    TO ROLE NEXUS_DATA_ENGINEER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Task para enriquecimento automático a cada hora
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK CORE.TASK_ENRICH_DOCUMENTS
    WAREHOUSE  = NEXUS_COMPUTE_WH
    SCHEDULE   = 'USING CRON 0 * * * * UTC'
    COMMENT    = 'Enriquece documentos não classificados com Cortex AI'
AS
    CALL CORE.ENRICH_DOCUMENTS_WITH_AI('ALL');

ALTER TASK CORE.TASK_ENRICH_DOCUMENTS RESUME;
