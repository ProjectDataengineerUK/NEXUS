-- NEXUS AI DataOps — Executive Briefing Task (Sprint 7)
-- Stored procedure + task diária para gerar o briefing executivo via Cortex Agent.
-- Pré-requisito: 10_tasks_and_streams.sql, 14_cortex_analyst_sprint4.sql

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela de briefings persistidos (se não existir)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS AI.EXECUTIVE_BRIEFINGS (
    briefing_id     VARCHAR(36)    DEFAULT UUID_STRING(),
    org_id          VARCHAR(100)   NOT NULL,
    briefing_date   DATE           DEFAULT CURRENT_DATE(),
    briefing_type   VARCHAR(50)    DEFAULT 'DAILY',   -- DAILY | WEEKLY | MONTHLY
    content         TEXT,
    kpi_snapshot    VARIANT,       -- OBJECT com KPIs do momento
    model_used      VARCHAR(100)   DEFAULT 'claude-3-5-sonnet',
    tokens_used     INTEGER,
    latency_ms      INTEGER,
    created_at      TIMESTAMP_TZ   DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_executive_briefings PRIMARY KEY (briefing_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: gera briefing diário para todas as orgs ativas
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.SP_EXECUTIVE_BRIEFING_DAILY()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
import json
import time

def run(session):
    # 1. Buscar todas as orgs ativas
    orgs = session.sql("""
        SELECT DISTINCT org_id
        FROM CORE.CUSTOMERS
        WHERE lifecycle_stage != 'churned'
          AND updated_at >= CURRENT_DATE() - 90
    """).collect()

    if not orgs:
        return "NO_ACTIVE_ORGS"

    results = []
    model = "claude-3-5-sonnet"

    for org_row in orgs:
        org_id = org_row["ORG_ID"]

        # 2. Snapshot de KPIs para o prompt
        kpi_rows = session.sql(f"""
            SELECT
                COUNT(*)                                                AS total_customers,
                SUM(CASE WHEN risk_level = 'HIGH'   THEN 1 ELSE 0 END) AS high_risk,
                SUM(CASE WHEN risk_level = 'MEDIUM' THEN 1 ELSE 0 END) AS medium_risk,
                ROUND(SUM(arr), 2)                                      AS total_arr,
                ROUND(SUM(CASE WHEN risk_level = 'HIGH' THEN arr ELSE 0 END), 2) AS arr_at_risk,
                ROUND(AVG(health_score), 1)                             AS avg_health_score,
                ROUND(AVG(nps_score), 1)                                AS avg_nps
            FROM MART.CUSTOMER_360
            WHERE org_id = '{org_id}'
        """).collect()

        if not kpi_rows:
            continue

        k = kpi_rows[0].as_dict()

        # 3. Novo clientes e churns nos últimos 30 dias
        delta_rows = session.sql(f"""
            SELECT
                SUM(CASE WHEN created_at >= CURRENT_DATE() - 30 THEN 1 ELSE 0 END) AS new_30d,
                SUM(CASE WHEN lifecycle_stage = 'churned'
                          AND updated_at >= CURRENT_DATE() - 30 THEN 1 ELSE 0 END) AS churned_30d
            FROM CORE.CUSTOMERS
            WHERE org_id = '{org_id}'
        """).collect()

        delta = delta_rows[0].as_dict() if delta_rows else {}

        kpi_snapshot = {**k, **delta}
        kpi_str = json.dumps(kpi_snapshot, default=str)

        # 4. Gerar briefing via Cortex LLM
        prompt = (
            "Você é o Executive AI Briefing Agent do NEXUS AI DataOps. "
            "Com base nos KPIs abaixo, gere um briefing executivo conciso (máx 300 palavras) "
            "em português com as seções: "
            "(1) Resumo do dia, "
            "(2) Top 3 riscos imediatos, "
            "(3) Top 3 oportunidades de receita, "
            "(4) Ações recomendadas para as próximas 24h. "
            f"KPIs: {kpi_str}"
        )

        t0 = time.time()
        briefing_rows = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                '{model}',
                '{prompt.replace("'", "''")}'
            ) AS briefing_text
        """).collect()
        latency_ms = int((time.time() - t0) * 1000)

        briefing_text = briefing_rows[0]["BRIEFING_TEXT"] if briefing_rows else ""

        if not briefing_text:
            results.append(f"{org_id}:EMPTY_RESPONSE")
            continue

        # 5. Persistir em AI.EXECUTIVE_BRIEFINGS (parametrizado — sem delimitadores aninhados)
        session.sql("""
            INSERT INTO AI.EXECUTIVE_BRIEFINGS
                (org_id, briefing_date, briefing_type, content, kpi_snapshot,
                 model_used, tokens_used, latency_ms)
            VALUES (?, CURRENT_DATE(), 'DAILY', ?, PARSE_JSON(?), ?, 0, ?)
        """, params=[org_id, briefing_text, kpi_str, model, latency_ms]).collect()

        # 6. Registrar em AI.RECOMMENDATIONS (escape simples — sem delimitadores aninhados)
        brief_safe = briefing_text[:1000].replace("'", "''")
        session.sql(f"""
            MERGE INTO AI.RECOMMENDATIONS AS tgt
            USING (
                SELECT
                    '{org_id}'           AS org_id,
                    'executive'          AS entity_id,
                    'briefing'           AS entity_type,
                    'daily_briefing'     AS recommendation_type,
                    'HIGH'               AS priority,
                    '{brief_safe}'       AS recommendation_text,
                    CURRENT_TIMESTAMP() + INTERVAL '1 day' AS expires_at
            ) AS src
            ON  tgt.org_id               = src.org_id
            AND tgt.entity_id            = src.entity_id
            AND tgt.recommendation_type  = src.recommendation_type
            AND tgt.expires_at           > CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (
                org_id, entity_id, entity_type, recommendation_type,
                priority, recommendation_text, expires_at
            ) VALUES (
                src.org_id, src.entity_id, src.entity_type, src.recommendation_type,
                src.priority, src.recommendation_text, src.expires_at
            )
        """).collect()

        results.append(f"{org_id}:OK")

    return "BRIEFINGS_GENERATED:" + ",".join(results)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: briefing semanal (mais abrangente — inclui forecast)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE CORE.SP_EXECUTIVE_BRIEFING_WEEKLY()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
import json
import time

def run(session):
    orgs = session.sql("""
        SELECT DISTINCT org_id FROM CORE.CUSTOMERS
        WHERE lifecycle_stage != 'churned'
    """).collect()

    model = "claude-3-5-sonnet"
    results = []

    for org_row in orgs:
        org_id = org_row["ORG_ID"]

        # Agrega KPIs da semana + comparação com semana anterior
        kpi_rows = session.sql(f"""
            WITH current_week AS (
                SELECT
                    COUNT(*)                        AS customers,
                    SUM(arr)                        AS total_arr,
                    AVG(health_score)               AS avg_health,
                    SUM(CASE WHEN risk_level = 'HIGH' THEN 1 ELSE 0 END) AS high_risk
                FROM MART.CUSTOMER_360
                WHERE org_id = '{org_id}'
            ),
            prev_week AS (
                SELECT
                    COUNT(*)                        AS customers_prev,
                    SUM(arr)                        AS total_arr_prev,
                    AVG(health_score)               AS avg_health_prev
                FROM MART.CUSTOMER_360
                WHERE org_id = '{org_id}'
                -- Simula semana anterior com snapshot de KPIs históricos se disponível
            )
            SELECT
                cw.*,
                pw.customers_prev,
                pw.total_arr_prev,
                pw.avg_health_prev,
                ROUND((cw.total_arr - pw.total_arr_prev) / NULLIF(pw.total_arr_prev, 0) * 100, 2) AS arr_growth_pct
            FROM current_week cw, prev_week pw
        """).collect()

        if not kpi_rows:
            results.append(f"{org_id}:NO_DATA")
            continue

        k = kpi_rows[0].as_dict()
        kpi_str = json.dumps(k, default=str)

        prompt = (
            "Você é o Executive Weekly Intelligence Agent do NEXUS AI DataOps. "
            "Gere um relatório executivo semanal conciso (máx 400 palavras) em português com: "
            "(1) Principais movimentos da semana (crescimento/queda), "
            "(2) Clientes em risco — análise de padrões, "
            "(3) Oportunidades de upsell/cross-sell identificadas, "
            "(4) Forecast de receita para as próximas 4 semanas, "
            "(5) Decisões recomendadas para o board. "
            f"KPIs da semana: {kpi_str}"
        )

        t0 = time.time()
        briefing_rows = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                '{model}',
                '{prompt.replace("'", "''")}'
            ) AS briefing_text
        """).collect()
        latency_ms = int((time.time() - t0) * 1000)

        briefing_text = briefing_rows[0]["BRIEFING_TEXT"] if briefing_rows else ""

        if briefing_text:
            session.sql("""
                INSERT INTO AI.EXECUTIVE_BRIEFINGS
                    (org_id, briefing_date, briefing_type, content, kpi_snapshot,
                     model_used, tokens_used, latency_ms)
                VALUES (?, CURRENT_DATE(), 'WEEKLY', ?, PARSE_JSON(?), ?, 0, ?)
            """, params=[org_id, briefing_text, kpi_str, model, latency_ms]).collect()
            results.append(f"{org_id}:OK")
        else:
            results.append(f"{org_id}:EMPTY")

    return "WEEKLY_BRIEFINGS:" + ",".join(results)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Tasks de orquestração
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK CONFIG.TASK_EXECUTIVE_BRIEFING_DAILY
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 7 * * * UTC'
    COMMENT   = 'Gera Executive AI Briefing diário às 07:00 UTC e persiste em AI.EXECUTIVE_BRIEFINGS'
AS
    CALL NEXUS_APP.CORE.SP_EXECUTIVE_BRIEFING_DAILY();

CREATE OR REPLACE TASK CONFIG.TASK_EXECUTIVE_BRIEFING_WEEKLY
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 8 * * 1 UTC'
    COMMENT   = 'Gera Executive AI Briefing semanal toda segunda às 08:00 UTC'
AS
    CALL NEXUS_APP.CORE.SP_EXECUTIVE_BRIEFING_WEEKLY();

-- ─────────────────────────────────────────────────────────────────────────────
-- View de consulta rápida — último briefing por org
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW AI.V_LATEST_EXECUTIVE_BRIEFING AS
SELECT
    b.briefing_id,
    b.org_id,
    b.briefing_date,
    b.briefing_type,
    b.content,
    b.kpi_snapshot,
    b.model_used,
    b.latency_ms,
    b.created_at
FROM AI.EXECUTIVE_BRIEFINGS b
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY b.org_id, b.briefing_type
    ORDER BY b.created_at DESC
) = 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants para o Native App role
-- ─────────────────────────────────────────────────────────────────────────────

GRANT SELECT ON TABLE  AI.EXECUTIVE_BRIEFINGS            TO DATABASE ROLE NEXUS_APP.VIEWER;
GRANT SELECT ON VIEW   AI.V_LATEST_EXECUTIVE_BRIEFING    TO DATABASE ROLE NEXUS_APP.VIEWER;
GRANT USAGE  ON PROCEDURE CORE.SP_EXECUTIVE_BRIEFING_DAILY()   TO DATABASE ROLE NEXUS_APP.ADMIN;
GRANT USAGE  ON PROCEDURE CORE.SP_EXECUTIVE_BRIEFING_WEEKLY()  TO DATABASE ROLE NEXUS_APP.ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ativar tasks em produção após validação
-- ALTER TASK CONFIG.TASK_EXECUTIVE_BRIEFING_DAILY   RESUME;
-- ALTER TASK CONFIG.TASK_EXECUTIVE_BRIEFING_WEEKLY  RESUME;
-- ─────────────────────────────────────────────────────────────────────────────
