-- NEXUS AI DataOps — Cortex Search: Contract Intelligence
-- Serviço de busca semântica dedicado a contratos.
-- Separado do serviço customer_docs para isolar acesso e latência.

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─── View de chunks de contratos (input para o search service) ────────────────

CREATE OR REPLACE VIEW AI.CONTRACT_CHUNKS_V AS
SELECT
    ch.chunk_id,
    ch.document_id,
    ch.chunk_text,
    ch.chunk_index,
    ch.section_title,
    d.document_name          AS contract_name,
    d.document_type,
    d.org_id,
    d.entity_id              AS customer_id,
    c.name                   AS customer_name,
    d.contract_type,
    d.contract_value_usd,
    d.start_date,
    d.end_date,
    d.auto_renewal,
    d.governing_law,
    d.ai_summary             AS contract_summary
FROM AI.DOCUMENT_CHUNKS ch
JOIN CORE.DOCUMENTS d
     ON ch.document_id = d.document_id
LEFT JOIN CORE.CUSTOMERS c
     ON d.entity_id = c.customer_id AND d.org_id = c.org_id
WHERE d.document_type IN ('contract', 'sla', 'amendment', 'addendum')
  AND ch.chunk_text  IS NOT NULL;


-- ─── Cortex Search Service: CONTRACT_SEARCH ──────────────────────────────────

CREATE OR REPLACE CORTEX SEARCH SERVICE AI.CONTRACT_SEARCH
    ON chunk_text
    ATTRIBUTES
        document_id,
        contract_name,
        customer_name,
        customer_id,
        org_id,
        document_type,
        section_title,
        contract_type,
        contract_value_usd,
        start_date,
        end_date,
        auto_renewal,
        contract_summary
    WAREHOUSE = NEXUS_COMPUTE_WH
    TARGET_LAG = '1 hour'
    AS
        SELECT * FROM AI.CONTRACT_CHUNKS_V;


-- ─── Stored Procedure: contrato search helper ─────────────────────────────────

CREATE OR REPLACE PROCEDURE AI.SEARCH_CONTRACTS(
    query       VARCHAR,
    org_id      VARCHAR,
    max_results INTEGER DEFAULT 5
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'search'
AS $$
def search(session, query: str, org_id: str, max_results: int):
    from snowflake.core import Root
    root = Root(session)

    svc = (
        root
        .databases["NEXUS_APP"]
        .schemas["AI"]
        .cortex_search_services["CONTRACT_SEARCH"]
    )

    resp = svc.search(
        query=query,
        columns=["chunk_text", "contract_name", "customer_name",
                 "section_title", "contract_type", "document_id",
                 "contract_value_usd", "end_date", "auto_renewal"],
        filter={"@eq": {"org_id": org_id}},
        limit=max_results,
    )
    return resp.results
$$;
