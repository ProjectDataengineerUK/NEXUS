-- NEXUS AI DataOps — Tasks e Streams de Orquestração

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_ORCHESTRATION_WH;

-- Stream para detectar novos documentos não processados
CREATE OR REPLACE STREAM NEXUS_APP.CONFIG.DOCUMENTS_PENDING_STREAM
    ON TABLE NEXUS_APP.CORE.DOCUMENTS
    COMMENT = 'Detecta novos documentos para processar embeddings';

-- Stream para audit de novos agent messages
CREATE OR REPLACE STREAM NEXUS_APP.CONFIG.AGENT_MESSAGES_STREAM
    ON TABLE NEXUS_APP.AI.AGENT_MESSAGES
    COMMENT = 'Detecta novas mensagens para registrar em AUDIT.PROMPT_LOG';

-- Task: Data Quality checks diários (06:00 UTC)
CREATE OR REPLACE TASK NEXUS_APP.CONFIG.TASK_DATA_QUALITY
    WAREHOUSE = NEXUS_ORCHESTRATION_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
    COMMENT = 'Executa Data Metric Functions e registra em AUDIT.DATA_QUALITY_RESULTS'
AS
BEGIN
    INSERT INTO NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
        (org_id, table_name, metric_name, metric_value, threshold, status, details)
    SELECT
        'default' AS org_id,
        'NEXUS_APP.CORE.CUSTOMERS' AS table_name,
        'freshness_hours' AS metric_name,
        DATEDIFF('hour', MAX(updated_at), CURRENT_TIMESTAMP()) AS metric_value,
        24 AS threshold,
        CASE WHEN DATEDIFF('hour', MAX(updated_at), CURRENT_TIMESTAMP()) <= 24 THEN 'PASS' ELSE 'FAIL' END AS status,
        OBJECT_CONSTRUCT('last_update', MAX(updated_at)::VARCHAR) AS details
    FROM NEXUS_APP.CORE.CUSTOMERS;

    INSERT INTO NEXUS_APP.AUDIT.DATA_QUALITY_RESULTS
        (org_id, table_name, metric_name, metric_value, threshold, status)
    WITH today_count AS (
        SELECT COUNT(*) AS cnt FROM NEXUS_APP.CORE.TRANSACTIONS
        WHERE transaction_date = CURRENT_DATE()
    ),
    yesterday_count AS (
        SELECT COUNT(*) AS cnt FROM NEXUS_APP.CORE.TRANSACTIONS
        WHERE transaction_date = CURRENT_DATE() - 1
    )
    SELECT
        'default', 'NEXUS_APP.CORE.TRANSACTIONS', 'row_count_delta_pct',
        ABS(t.cnt - y.cnt) / NULLIF(y.cnt, 0) * 100,
        20,
        CASE WHEN ABS(t.cnt - y.cnt) / NULLIF(y.cnt, 0) * 100 <= 20 THEN 'PASS' ELSE 'WARN' END
    FROM today_count t, yesterday_count y;

    RETURN 'Data quality checks completed';
END;

-- Task: Geração de AI Briefing semanal (segunda-feira 08:00 UTC)
CREATE OR REPLACE TASK NEXUS_APP.CONFIG.TASK_WEEKLY_BRIEFING
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE = 'USING CRON 0 8 * * 1 UTC'
    COMMENT = 'Gera Executive AI Briefing semanal e armazena em AI.RECOMMENDATIONS'
AS
BEGIN
    LET briefing_text TEXT;

    SELECT SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        CONCAT(
            'Você é o Executive AI Briefing Agent do NEXUS AI DataOps. ',
            'Com base nos KPIs abaixo, gere um briefing executivo conciso (máx 300 palavras) ',
            'com: (1) principais mudanças da semana, (2) top 3 riscos, (3) top 3 oportunidades, ',
            '(4) ações recomendadas. Dados: ',
            (SELECT OBJECT_CONSTRUCT(
                'total_customers', COUNT(*),
                'high_risk_customers', SUM(CASE WHEN cs.risk_level = 'HIGH' THEN 1 ELSE 0 END),
                'arr_at_risk', SUM(CASE WHEN cs.risk_level = 'HIGH' THEN c.arr ELSE 0 END)
            )::VARCHAR
            FROM NEXUS_APP.CORE.CUSTOMERS c
            LEFT JOIN NEXUS_APP.AI.CHURN_SCORES cs ON cs.customer_id = c.customer_id
            WHERE cs.scored_at >= CURRENT_DATE() - 7)
        )
    ) INTO :briefing_text;

    INSERT INTO NEXUS_APP.AI.RECOMMENDATIONS
        (org_id, entity_id, entity_type, recommendation_type, priority,
         recommendation_text, expires_at)
    VALUES
        ('default', 'executive', 'briefing', 'weekly_briefing', 'HIGH',
         :briefing_text, CURRENT_TIMESTAMP() + INTERVAL '7 days');

    RETURN 'Weekly briefing generated';
END;

-- Task: Refresh de churn scores diário (02:00 UTC, após marts dbt)
CREATE OR REPLACE TASK NEXUS_APP.CONFIG.TASK_CHURN_SCORING
    WAREHOUSE = NEXUS_ML_WH
    SCHEDULE = 'USING CRON 0 2 * * * UTC'
    COMMENT = 'Executa inference do modelo de churn e atualiza AI.CHURN_SCORES'
AS
    CALL NEXUS_APP.AI.RUN_CHURN_SCORING();

-- Ativar tasks em produção após validação
-- ALTER TASK NEXUS_APP.CONFIG.TASK_DATA_QUALITY    RESUME;
-- ALTER TASK NEXUS_APP.CONFIG.TASK_WEEKLY_BRIEFING RESUME;
-- ALTER TASK NEXUS_APP.CONFIG.TASK_CHURN_SCORING   RESUME;
