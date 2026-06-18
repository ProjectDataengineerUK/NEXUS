-- =============================================================================
-- NEXUS AI DataOps — Contract Intelligence
-- AI-powered clause extraction, risk detection and contract insights
-- =============================================================================

USE SCHEMA NEXUS_APP.CORE;

-- ─── Extend DOCUMENTS table for contract metadata ────────────────────────────

ALTER TABLE NEXUS_APP.CORE.DOCUMENTS
    ADD COLUMN IF NOT EXISTS contract_type      VARCHAR(100),
    ADD COLUMN IF NOT EXISTS contract_value_usd NUMBER(18,2),
    ADD COLUMN IF NOT EXISTS start_date         DATE,
    ADD COLUMN IF NOT EXISTS end_date           DATE,
    ADD COLUMN IF NOT EXISTS auto_renewal       BOOLEAN     DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS governing_law      VARCHAR(200),
    ADD COLUMN IF NOT EXISTS clauses_extracted  VARIANT,
    ADD COLUMN IF NOT EXISTS risk_flags         VARIANT,
    ADD COLUMN IF NOT EXISTS ai_summary         VARCHAR(4000),
    ADD COLUMN IF NOT EXISTS extraction_status  VARCHAR(50)  DEFAULT 'pending';


-- ─── SP: Extract contract clauses using Cortex AI ────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.EXTRACT_CONTRACT_CLAUSES(doc_id VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_content   VARCHAR;
    v_response  VARCHAR;
    v_result    VARIANT;
BEGIN
    SELECT content INTO v_content
    FROM NEXUS_APP.CORE.DOCUMENTS
    WHERE document_id = :doc_id
      AND document_type = 'contract';

    IF (v_content IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Document not found or not a contract');
    END IF;

    -- Extract structured contract data via Cortex LLM
    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'role', 'system',
            'content', 'You are a legal contract analysis expert. Extract structured data from contracts and return ONLY valid JSON, no markdown, no explanation.'
        ), OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Analyze this contract and extract the following fields as JSON:
{
  "contract_type": "SaaS|Service Agreement|NDA|Employment|Other",
  "contract_value_usd": number or null,
  "start_date": "YYYY-MM-DD" or null,
  "end_date": "YYYY-MM-DD" or null,
  "auto_renewal": true|false,
  "governing_law": "jurisdiction string" or null,
  "payment_terms": "string" or null,
  "termination_clause": "string summary" or null,
  "liability_cap": "string" or null,
  "sla_commitments": ["string", ...],
  "key_obligations": ["string", ...],
  "risk_flags": ["description of potential risk", ...],
  "summary": "2-3 sentence executive summary in Portuguese"
}

CONTRACT TEXT:
' || LEFT(:v_content, 8000)
        ))
    ) INTO v_response;

    -- Parse JSON response
    v_result := TRY_PARSE_JSON(v_response);

    IF (v_result IS NULL) THEN
        -- Fallback: store raw response if JSON parse fails
        v_result := OBJECT_CONSTRUCT(
            'raw_response',    v_response,
            'parse_error',     TRUE,
            'risk_flags',      ARRAY_CONSTRUCT('Parsing failed — manual review required')
        );
    END IF;

    -- Update document with extracted data
    UPDATE NEXUS_APP.CORE.DOCUMENTS
    SET
        contract_type      = v_result:contract_type::VARCHAR,
        contract_value_usd = TRY_TO_NUMBER(v_result:contract_value_usd::VARCHAR),
        start_date         = TRY_TO_DATE(v_result:start_date::VARCHAR),
        end_date           = TRY_TO_DATE(v_result:end_date::VARCHAR),
        auto_renewal       = (v_result:auto_renewal::VARCHAR = 'true'),
        governing_law      = v_result:governing_law::VARCHAR,
        clauses_extracted  = v_result,
        risk_flags         = v_result:risk_flags,
        ai_summary         = v_result:summary::VARCHAR,
        extraction_status  = 'completed',
        updated_at         = CURRENT_TIMESTAMP()
    WHERE document_id = :doc_id;

    RETURN v_result;
END;
$$;


-- ─── View: contract intelligence dashboard ────────────────────────────────────

CREATE OR REPLACE VIEW NEXUS_APP.AI.V_CONTRACT_INTELLIGENCE AS
SELECT
    d.document_id,
    d.org_id,
    d.title                                                AS contract_name,
    d.customer_id,
    c.customer_name,
    d.contract_type,
    d.contract_value_usd,
    d.start_date,
    d.end_date,
    DATEDIFF('day', CURRENT_DATE(), d.end_date)            AS days_to_expiry,
    CASE
        WHEN DATEDIFF('day', CURRENT_DATE(), d.end_date) < 0    THEN 'EXPIRED'
        WHEN DATEDIFF('day', CURRENT_DATE(), d.end_date) <= 30  THEN 'EXPIRING_SOON'
        WHEN DATEDIFF('day', CURRENT_DATE(), d.end_date) <= 90  THEN 'RENEW_WATCH'
        ELSE 'ACTIVE'
    END                                                    AS renewal_status,
    d.auto_renewal,
    d.governing_law,
    ARRAY_SIZE(d.risk_flags)                               AS risk_flag_count,
    d.risk_flags,
    d.ai_summary,
    d.extraction_status,
    TO_CHAR(d.created_at, 'YYYY-MM-DD')                   AS uploaded_at
FROM NEXUS_APP.CORE.DOCUMENTS d
LEFT JOIN NEXUS_APP.MART.CUSTOMER_360 c
       ON d.customer_id = c.customer_id AND d.org_id = c.org_id
WHERE d.document_type = 'contract'
  AND d.is_active = TRUE;


-- ─── Task: extract clauses for pending contracts (every 4h) ──────────────────

CREATE OR REPLACE TASK CORE.TASK_CONTRACT_EXTRACTION
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 */4 * * * UTC'
    COMMENT   = 'Auto-extract clauses from newly uploaded contracts'
AS
DECLARE
    v_doc_id VARCHAR;
BEGIN
    FOR rec IN (
        SELECT document_id
        FROM NEXUS_APP.CORE.DOCUMENTS
        WHERE document_type    = 'contract'
          AND extraction_status = 'pending'
          AND content          IS NOT NULL
          AND is_active        = TRUE
        ORDER BY created_at
        LIMIT 20
    ) DO
        v_doc_id := rec.document_id;
        CALL CORE.EXTRACT_CONTRACT_CLAUSES(:v_doc_id);
    END FOR;
END;

ALTER TASK CORE.TASK_CONTRACT_EXTRACTION RESUME;
