-- Cortex Agent Tool Wrappers — Python Stored Procedures
-- Permitem que Cortex Agents executem ações via stored procedures
-- Cada SP é uma "tool" registrada nos YAMLs dos agentes.

-- ─────────────────────────────────────────────────────────────────────────────
-- SP 1: Atualiza status de uma recomendação de IA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.UPDATE_RECOMMENDATION_STATUS(
    recommendation_id VARCHAR,
    new_status        VARCHAR,
    acted_by          VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, recommendation_id: str, new_status: str, acted_by: str) -> str:
    valid_statuses = ('pending', 'in_progress', 'completed', 'dismissed', 'snoozed')
    if new_status not in valid_statuses:
        return f"ERROR: invalid status '{new_status}'. Must be one of: {valid_statuses}"

    result = session.sql("""
        UPDATE AI.RECOMMENDATIONS
        SET status   = ?,
            acted_at = CURRENT_TIMESTAMP()
        WHERE recommendation_id = ?
          AND is_active = TRUE
    """, params=[new_status, recommendation_id]).collect()

    rows = result[0]['number of rows updated'] if result else 0
    if rows == 0:
        return f"WARNING: recommendation {recommendation_id} not found or already inactive"

    session.sql("""
        INSERT INTO AUDIT.ACTION_LOG (org_id, user_name, action_type, entity_type, entity_id, payload)
        SELECT org_id, ?, 'UPDATE_STATUS', 'recommendation', ?, OBJECT_CONSTRUCT('new_status', ?)
        FROM AI.RECOMMENDATIONS WHERE recommendation_id = ?
    """, params=[acted_by, recommendation_id, new_status, recommendation_id]).collect()

    return f"OK: recommendation {recommendation_id} → {new_status}"
$$;

GRANT USAGE ON PROCEDURE CORE.UPDATE_RECOMMENDATION_STATUS(VARCHAR, VARCHAR, VARCHAR)
    TO ROLE NEXUS_ANALYST;

-- ─────────────────────────────────────────────────────────────────────────────
-- SP 2: Gera resumo executivo de narrativa via Cortex Complete
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.GENERATE_EXECUTIVE_SUMMARY(
    org_id    VARCHAR,
    model     VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, org_id: str, model: str = 'mistral-large2') -> str:
    kpis = session.sql("""
        SELECT total_arr, active_customers, at_risk_customers,
               arr_at_risk, avg_health_score, avg_nps,
               open_tickets, pending_recommendations
        FROM MART.EXECUTIVE_KPIS
        WHERE org_id = ?
        ORDER BY snapshot_date DESC
        LIMIT 1
    """, params=[org_id]).collect()

    if not kpis:
        return "No KPI data available for this org."

    row = kpis[0]
    prompt = f"""You are an executive business intelligence assistant.
Summarize the following KPIs in 3 concise bullet points for a C-level audience.
Focus on risks and opportunities. Be direct and quantitative.

ARR: ${row['TOTAL_ARR']:,.0f}
Active customers: {row['ACTIVE_CUSTOMERS']}
At-risk customers: {row['AT_RISK_CUSTOMERS']} (${row['ARR_AT_RISK']:,.0f} ARR at risk)
Avg health score: {row['AVG_HEALTH_SCORE']:.1f}/100
Avg NPS: {row['AVG_NPS']:.1f}
Open tickets: {row['OPEN_TICKETS']}
Pending AI recommendations: {row['PENDING_RECOMMENDATIONS']}

Provide a 3-bullet executive summary:"""

    result = session.sql(
        "SELECT SNOWFLAKE.CORTEX.COMPLETE(?, ?) AS summary",
        params=[model, prompt]
    ).collect()

    return result[0]['SUMMARY'] if result else "Unable to generate summary."
$$;

GRANT USAGE ON PROCEDURE CORE.GENERATE_EXECUTIVE_SUMMARY(VARCHAR, VARCHAR)
    TO ROLE NEXUS_ANALYST;
GRANT USAGE ON PROCEDURE CORE.GENERATE_EXECUTIVE_SUMMARY(VARCHAR, VARCHAR)
    TO ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SP 3: Registra sincronização com CRM externo (stub)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.LOG_CRM_SYNC(
    org_id         VARCHAR,
    entity_type    VARCHAR,
    entity_id      VARCHAR,
    crm_system     VARCHAR,
    sync_status    VARCHAR,
    initiated_by   VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session, org_id: str, entity_type: str, entity_id: str,
        crm_system: str, sync_status: str, initiated_by: str) -> str:
    session.sql("""
        INSERT INTO AUDIT.ACTION_LOG
            (org_id, user_name, action_type, entity_type, entity_id, payload)
        VALUES (?, ?, 'CRM_SYNC', ?, ?, OBJECT_CONSTRUCT(
            'crm_system', ?,
            'sync_status', ?,
            'initiated_at', CURRENT_TIMESTAMP()::VARCHAR
        ))
    """, params=[org_id, initiated_by, entity_type, entity_id,
                 crm_system, sync_status]).collect()

    return f"OK: CRM sync logged — {entity_type}/{entity_id} → {crm_system} ({sync_status})"
$$;

GRANT USAGE ON PROCEDURE CORE.LOG_CRM_SYNC(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR)
    TO ROLE NEXUS_ANALYST;
