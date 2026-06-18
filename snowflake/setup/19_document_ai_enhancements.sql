-- NEXUS AI DataOps — Document AI Enhancements
-- AI_CLASSIFY + AI_SUMMARIZE + AI_EXTRACT (COMPLETE) para enriquecimento
-- automático de documentos. Complementa o arquivo 13.

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Colunas adicionais em CORE.DOCUMENTS (idempotente)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS document_category  VARCHAR(100);
ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS document_summary   TEXT;
ALTER TABLE CORE.DOCUMENTS ADD COLUMN IF NOT EXISTS extracted_fields   VARIANT;

-- ─────────────────────────────────────────────────────────────────────────────
-- SP: CORE.ENRICH_DOCUMENTS_WITH_AI
-- Mantida para compatibilidade com o Streamlit existente.
-- Agora delega para AI.SP_PROCESS_DOCUMENT quando o documento tem texto.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(p_org_id VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS $$
def run(session, p_org_id: str) -> str:
    """
    Enriquece documentos ainda sem document_category.
    Delega o trabalho pesado para AI.SP_PROCESS_DOCUMENT para evitar
    duplicação de lógica Cortex entre as duas SPs.
    Suporta p_org_id = 'ALL' para processar todos os orgs.
    """
    org_filter = "" if p_org_id == "ALL" else f"AND org_id = '{p_org_id}'"

    rows = session.sql(f"""
        SELECT document_id, org_id
        FROM NEXUS_APP.CORE.DOCUMENTS
        WHERE processing_status = 'completed'
          AND (extracted_text IS NOT NULL OR document_id IN (
                  SELECT DISTINCT document_id FROM NEXUS_APP.AI.DOCUMENT_CHUNKS
              ))
          AND (document_category IS NULL OR document_category = '')
          {org_filter}
        LIMIT 50
    """).collect()

    updated = 0
    failed  = 0
    for r in rows:
        doc_id = r['DOCUMENT_ID']
        org_id = r['ORG_ID']
        result_rows = session.sql(f"""
            CALL NEXUS_APP.AI.SP_PROCESS_DOCUMENT('{doc_id}', '{org_id}')
        """).collect()
        msg = result_rows[0][0] if result_rows else 'ERROR: no return'
        if msg.startswith('OK'):
            updated += 1
        else:
            failed += 1

    return f"OK: {updated} enriched, {failed} failed"
$$;

GRANT USAGE ON PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(VARCHAR)
    TO ROLE NEXUS_DATA_ENGINEER;
GRANT USAGE ON PROCEDURE CORE.ENRICH_DOCUMENTS_WITH_AI(VARCHAR)
    TO ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SP: AI.SP_PROCESS_PENDING_DOCUMENTS
-- Processa em lote todos os documentos com processing_status = 'pending'
-- para um org_id. Chama AI.SP_PROCESS_DOCUMENT para cada um.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE NEXUS_APP.AI.SP_PROCESS_PENDING_DOCUMENTS(
    p_org_id VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'process_pending'
EXECUTE AS CALLER
AS $$
def process_pending(session, p_org_id: str) -> str:
    """
    Seleciona documentos com processing_status = 'pending' e processa cada um
    via AI.SP_PROCESS_DOCUMENT (classify + summarize + extract).

    Suporta p_org_id = 'ALL' para processar todos os orgs em uma execução.
    Processa até 100 documentos por chamada para controlar custo de créditos.
    """
    org_filter = (
        ""
        if p_org_id == "ALL"
        else f"AND org_id = '{p_org_id}'"
    )

    pending_rows = session.sql(f"""
        SELECT document_id, org_id
        FROM NEXUS_APP.CORE.DOCUMENTS
        WHERE processing_status = 'pending'
          {org_filter}
        ORDER BY created_at ASC
        LIMIT 100
    """).collect()

    if not pending_rows:
        return "OK: 0 pending documents found"

    total     = len(pending_rows)
    completed = 0
    failed    = 0
    errors    = []

    for row in pending_rows:
        doc_id = row['DOCUMENT_ID']
        org_id = row['ORG_ID']

        # Marca como 'processing' para evitar double-processing em execuções
        # paralelas da task (idempotente: não reprocessa se já mudou de estado)
        session.sql(f"""
            UPDATE NEXUS_APP.CORE.DOCUMENTS
            SET processing_status = 'processing'
            WHERE document_id = '{doc_id}'
              AND processing_status = 'pending'
        """).collect()

        try:
            result_rows = session.sql(f"""
                CALL NEXUS_APP.AI.SP_PROCESS_DOCUMENT('{doc_id}', '{org_id}')
            """).collect()

            msg = result_rows[0][0] if result_rows else 'ERROR: no return'

            if msg.startswith('OK'):
                # SP_PROCESS_DOCUMENT já atualiza para 'completed'
                completed += 1
            else:
                # SP_PROCESS_DOCUMENT já atualiza para 'failed'
                failed += 1
                errors.append(f"{doc_id}:{msg[:80]}")

        except Exception as exc:
            failed += 1
            errors.append(f"{doc_id}:{str(exc)[:80]}")
            # Garante que o status não fica preso em 'processing'
            try:
                session.sql(f"""
                    UPDATE NEXUS_APP.CORE.DOCUMENTS
                    SET processing_status = 'failed',
                        processed_at      = CURRENT_TIMESTAMP()
                    WHERE document_id = '{doc_id}'
                      AND processing_status = 'processing'
                """).collect()
            except Exception:
                pass

    summary = f"OK: {total} found — {completed} completed, {failed} failed"
    if errors:
        summary += " | errors: " + "; ".join(errors[:5])
        if len(errors) > 5:
            summary += f" (+{len(errors) - 5} more)"
    return summary
$$;

GRANT USAGE ON PROCEDURE NEXUS_APP.AI.SP_PROCESS_PENDING_DOCUMENTS(VARCHAR)
    TO ROLE NEXUS_ADMIN;
GRANT USAGE ON PROCEDURE NEXUS_APP.AI.SP_PROCESS_PENDING_DOCUMENTS(VARCHAR)
    TO ROLE NEXUS_DATA_ENGINEER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Task para processamento automático de pendentes a cada hora
-- Substitui a task anterior CORE.TASK_ENRICH_DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────

-- Mantém compatibilidade: task antiga continua rodando ENRICH para docs
-- que ficaram sem category mesmo após processamento inicial
CREATE OR REPLACE TASK CORE.TASK_ENRICH_DOCUMENTS
    WAREHOUSE  = NEXUS_COMPUTE_WH
    SCHEDULE   = 'USING CRON 0 * * * * UTC'
    COMMENT    = 'Enriquece documentos completed sem category com Cortex AI'
AS
    CALL NEXUS_APP.CORE.ENRICH_DOCUMENTS_WITH_AI('ALL');

ALTER TASK CORE.TASK_ENRICH_DOCUMENTS RESUME;

-- Nova task dedicada ao processamento de pendentes (a cada 15 min)
CREATE OR REPLACE TASK NEXUS_APP.AI.TASK_PROCESS_PENDING_DOCUMENTS
    WAREHOUSE  = NEXUS_COMPUTE_WH
    SCHEDULE   = 'USING CRON */15 * * * * UTC'
    COMMENT    = 'Processa documentos pending com CLASSIFY + SUMMARIZE + EXTRACT'
AS
    CALL NEXUS_APP.AI.SP_PROCESS_PENDING_DOCUMENTS('ALL');

ALTER TASK NEXUS_APP.AI.TASK_PROCESS_PENDING_DOCUMENTS RESUME;

GRANT MONITOR, OPERATE ON TASK NEXUS_APP.AI.TASK_PROCESS_PENDING_DOCUMENTS TO ROLE NEXUS_ADMIN;
