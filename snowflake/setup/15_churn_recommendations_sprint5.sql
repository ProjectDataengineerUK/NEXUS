-- NEXUS AI DataOps — Sprint 5: Churn Model + Recommendation Engine
-- Stage ML, Stored Procedures, sample data e Task de automação.

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stage para artefatos de modelos ML (Snowpark ML)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS NEXUS_APP.CORE.ML_STAGE
    DIRECTORY         = (ENABLE = TRUE)
    ENCRYPTION        = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT           = 'Artefatos de modelos Snowpark ML';

GRANT READ  ON STAGE NEXUS_APP.CORE.ML_STAGE TO ROLE NEXUS_ADMIN;
GRANT WRITE ON STAGE NEXUS_APP.CORE.ML_STAGE TO ROLE NEXUS_ADMIN;
GRANT READ  ON STAGE NEXUS_APP.CORE.ML_STAGE TO ROLE NEXUS_ANALYST;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: Pipeline de churn (scoring + recomendações)
-- Chama churn_model.py via Snowpark Python
-- ─────────────────────────────────────────────────────────────────────────────

-- NOTE: SP_RUN_CHURN_PIPELINE requer upload prévio de churn_model.py no ML_STAGE.
-- Executar SOMENTE após o upload do handler via 04-release ou scripts/upload_ml_model.py.
--
-- CREATE OR REPLACE PROCEDURE NEXUS_APP.CORE.SP_RUN_CHURN_PIPELINE(MODE VARCHAR DEFAULT 'full')
-- RETURNS VARCHAR
-- LANGUAGE PYTHON
-- RUNTIME_VERSION = '3.11'
-- PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
-- HANDLER = 'churn_model.run_churn_pipeline'
-- IMPORTS = ('@NEXUS_APP.CORE.ML_STAGE/churn_model.py')
-- COMMENT = 'Treina/executa modelo de churn e gera recomendações via Cortex';
--
-- GRANT EXECUTE ON PROCEDURE NEXUS_APP.CORE.SP_RUN_CHURN_PIPELINE(VARCHAR)
--     TO ROLE NEXUS_ADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Stored Procedure: Atualizar status de recomendação (Action Center)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE NEXUS_APP.CORE.SP_UPDATE_RECOMMENDATION(
    P_RECOMMENDATION_ID VARCHAR,
    P_STATUS            VARCHAR,
    P_NOTES             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE NEXUS_APP.AI.RECOMMENDATIONS
    SET
        status   = :P_STATUS,
        acted_at = CASE WHEN :P_STATUS IN ('completed','dismissed') THEN CURRENT_TIMESTAMP() ELSE acted_at END,
        is_active = CASE WHEN :P_STATUS IN ('completed','dismissed') THEN FALSE ELSE is_active END
    WHERE recommendation_id = :P_RECOMMENDATION_ID;

    INSERT INTO NEXUS_APP.AUDIT.ACTION_LOG
        (org_id, user_name, action_type, object_type, object_id, details)
    SELECT
        r.org_id,
        CURRENT_USER(),
        'recommendation_' || :P_STATUS,
        'recommendation',
        :P_RECOMMENDATION_ID,
        OBJECT_CONSTRUCT('notes', :P_NOTES, 'new_status', :P_STATUS)
    FROM NEXUS_APP.AI.RECOMMENDATIONS r
    WHERE r.recommendation_id = :P_RECOMMENDATION_ID;

    RETURN 'OK: recomendação ' || :P_RECOMMENDATION_ID || ' → ' || :P_STATUS;
END;
$$;

GRANT USAGE ON PROCEDURE NEXUS_APP.CORE.SP_UPDATE_RECOMMENDATION(VARCHAR, VARCHAR, VARCHAR)
    TO ROLE NEXUS_ANALYST;
GRANT USAGE ON PROCEDURE NEXUS_APP.CORE.SP_UPDATE_RECOMMENDATION(VARCHAR, VARCHAR, VARCHAR)
    TO ROLE NEXUS_VIEWER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Dynamic Table: visão consolidada de ações pendentes (Action Center)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.ACTION_CENTER
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Fila de ações priorizadas combinando churn e recomendações'
AS
SELECT
    r.recommendation_id,
    r.org_id,
    r.entity_id                                                          AS customer_id,
    c.name                                                               AS customer_name,
    c.segment,
    r.recommendation_type,
    r.priority,
    r.recommendation_text,
    r.expected_impact_usd,
    r.confidence_score,
    r.owner_role,
    r.status,
    r.created_at,
    r.expires_at,
    r.acted_at,

    -- Dados do cliente para contexto
    c360.health_score,
    c360.churn_risk_level,
    c360.churn_probability,
    c360.arr,
    c360.nearest_renewal_date,
    c360.nps_score,
    c360.open_tickets,

    -- Score de prioridade para ordenação
    CASE r.priority
        WHEN 'HIGH'   THEN 3
        WHEN 'MEDIUM' THEN 2
        ELSE               1
    END * (1 + COALESCE(r.expected_impact_usd, 0) / 100000) AS priority_score

FROM NEXUS_APP.AI.RECOMMENDATIONS r
JOIN NEXUS_APP.CORE.CUSTOMERS c
    ON r.entity_id = c.customer_id AND r.org_id = c.org_id
LEFT JOIN NEXUS_APP.MART.CUSTOMER_360 c360
    ON r.entity_id = c360.customer_id
WHERE r.is_active   = TRUE
  AND r.status NOT IN ('completed', 'dismissed');

GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.ACTION_CENTER TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.ACTION_CENTER TO ROLE NEXUS_VIEWER;

-- ─────────────────────────────────────────────────────────────────────────────
-- Task: Roda pipeline de churn diariamente às 03:00 UTC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TASK NEXUS_APP.CORE.TASK_DAILY_CHURN_PIPELINE
    WAREHOUSE = NEXUS_COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 3 * * * UTC'
    COMMENT   = 'Executa scoring de churn + geração de recomendações diariamente'
AS
    CALL NEXUS_APP.CORE.SP_RUN_CHURN_PIPELINE('full');

-- ALTER TASK NEXUS_APP.CORE.TASK_DAILY_CHURN_PIPELINE RESUME;  -- descomentar em prod

-- ─────────────────────────────────────────────────────────────────────────────
-- Dados demo: Churn Scores iniciais (sem executar o modelo ML)
-- ─────────────────────────────────────────────────────────────────────────────

MERGE INTO NEXUS_APP.AI.CHURN_SCORES tgt
USING (
    SELECT v.*
    FROM (VALUES
        ('CUST-001', 'ORG-DEMO-001', 0.1200, 'LOW',
         PARSE_JSON('["perfil_de_risco_moderado"]'),
         'Manter cadência padrão e monitorar próxima renovação',
         14400.00),
        ('CUST-002', 'ORG-DEMO-001', 0.7850, 'HIGH',
         PARSE_JSON('["baixo_engajamento","multiplas_violacoes_sla","nps_muito_baixo"]'),
         'Contato imediato do CSM + escalar violações de SLA urgentemente',
         235500.00),
        ('CUST-003', 'ORG-DEMO-001', 0.0450, 'LOW',
         PARSE_JSON('["perfil_de_risco_moderado"]'),
         'Manter cadência padrão — cliente champion, explorar oportunidade de upsell',
         3240.00),
        ('CUST-004', 'ORG-DEMO-001', 0.4200, 'MEDIUM',
         PARSE_JSON('["acumulo_de_tickets","baixo_mrr"]'),
         'Revisar tickets em aberto e agendar check-in mensal',
         50400.00),
        ('CUST-005', 'ORG-DEMO-001', 0.0300, 'LOW',
         PARSE_JSON('["perfil_de_risco_moderado"]'),
         'Cliente estável — identificar oportunidade de expansão de licenças',
         900.00)
    ) AS v (customer_id, org_id, churn_probability, risk_level,
            top_drivers, recommended_action, expected_revenue_at_risk)
) src
ON tgt.customer_id = src.customer_id AND tgt.org_id = src.org_id
WHEN MATCHED THEN UPDATE SET
    churn_probability        = src.churn_probability,
    risk_level               = src.risk_level,
    top_drivers              = src.top_drivers,
    recommended_action       = src.recommended_action,
    expected_revenue_at_risk = src.expected_revenue_at_risk,
    model_version            = '1.0.0-demo',
    scored_at                = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (org_id, customer_id, churn_probability, risk_level,
     top_drivers, recommended_action, expected_revenue_at_risk, model_version)
VALUES
    (src.org_id, src.customer_id, src.churn_probability, src.risk_level,
     src.top_drivers, src.recommended_action, src.expected_revenue_at_risk, '1.0.0-demo');

-- ─────────────────────────────────────────────────────────────────────────────
-- Dados demo: Recomendações iniciais para o Action Center
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO NEXUS_APP.AI.RECOMMENDATIONS
    (org_id, entity_id, entity_type, recommendation_type,
     priority, recommendation_text, expected_impact_usd,
     confidence_score, owner_role, status)
SELECT * FROM (VALUES
    -- Churn prevention — HIGH
    ('ORG-DEMO-001', 'CUST-002', 'customer', 'churn_prevention',
     'HIGH',
     'Agendar reunião de emergência com CEO da Quantum Finance em até 48h. Oferecer crédito SLA e designar CSM dedicado para recuperação do relacionamento.',
     235500.00, 0.7850, 'customer_success', 'pending'),

    -- Churn prevention — MEDIUM
    ('ORG-DEMO-001', 'CUST-004', 'customer', 'churn_prevention',
     'MEDIUM',
     'Resolver os 3 tickets críticos em aberto da Apex Telecom até o fim da semana. Agendar QBR trimestral para alinhar roadmap.',
     50400.00, 0.4200, 'customer_success', 'pending'),

    -- Upsell opportunity — Stellar SaaS
    ('ORG-DEMO-001', 'CUST-003', 'customer', 'upsell_opportunity',
     'MEDIUM',
     'Stellar SaaS atingiu 95% da capacidade de eventos do plano atual. Apresentar proposta de upgrade para Enterprise antes da renovação em 30 dias.',
     8640.00, 0.8200, 'sales', 'pending'),

    -- Upsell opportunity — Acme
    ('ORG-DEMO-001', 'CUST-001', 'customer', 'upsell_opportunity',
     'LOW',
     'Acme Corporation tem NPS 35 e uso crescente. Oportunidade de adicionar módulo de Analytics Avançado (+US$ 1.200/mês).',
     14400.00, 0.6000, 'sales', 'pending'),

    -- Contrato — Quantum Finance
    ('ORG-DEMO-001', 'CUST-002', 'customer', 'contract_review',
     'HIGH',
     'Contrato da Quantum Finance vence em 45 dias com cláusula de multa de US$ 50k por cancelamento antecipado. Iniciar renegociação com desconto de 15% para renovação anual.',
     300000.00, 0.9000, 'legal', 'pending'),

    -- Engajamento — Sunrise Pharma
    ('ORG-DEMO-001', 'CUST-005', 'customer', 'engagement',
     'LOW',
     'Sunrise Pharma não utilizou o módulo de Document Intelligence nos últimos 30 dias. Oferecer webinar de adoção e casos de uso para life sciences.',
     3600.00, 0.5500, 'customer_success', 'pending')
) AS v (org_id, entity_id, entity_type, recommendation_type,
        priority, recommendation_text, expected_impact_usd,
        confidence_score, owner_role, status)
WHERE NOT EXISTS (
    SELECT 1 FROM NEXUS_APP.AI.RECOMMENDATIONS r2
    WHERE r2.entity_id = v.entity_id
      AND r2.recommendation_type = v.recommendation_type
      AND r2.is_active = TRUE
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Verificação
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'CHURN_SCORES'    AS tabela, COUNT(*) AS registros FROM NEXUS_APP.AI.CHURN_SCORES
UNION ALL
SELECT 'RECOMMENDATIONS' AS tabela, COUNT(*) AS registros FROM NEXUS_APP.AI.RECOMMENDATIONS;
