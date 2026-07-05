-- NEXUS AI DataOps — Dynamic Tables para deploy no Native App
-- Sprint 2 — P1: DTs que chegam ao consumer via setup_script.sql
-- Este arquivo é referência standalone. O código canonico está em setup_script.sql.

USE DATABASE NEXUS_APP;

-- DT_EXECUTIVE_KPIS — KPIs executivos agregados por org
CREATE OR REPLACE DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'KPIs executivos por org — atualiza automaticamente a cada 1h'
AS
SELECT
    c.org_id,
    COUNT(DISTINCT c.customer_id)                             AS total_customers,
    ROUND(AVG(COALESCE(cs.churn_probability, 0.5)) * 100, 1) AS avg_churn_risk_pct,
    COUNT(CASE WHEN COALESCE(cs.churn_probability, 0.5) > 0.7 THEN 1 END)        AS critical_risk_count,
    COUNT(CASE WHEN c.lifecycle_stage = 'active' THEN 1 END)  AS active_customers,
    COALESCE(SUM(c.arr), 0)                                   AS total_arr,
    COALESCE(SUM(c.mrr), 0)                                   AS total_mrr,
    COALESCE(ROUND(AVG(c.nps_score), 1), 0)                  AS avg_nps,
    COUNT(CASE WHEN t.status = 'open' THEN 1 END)             AS open_tickets,
    CURRENT_TIMESTAMP()                                        AS refreshed_at
FROM CORE.CUSTOMERS c
LEFT JOIN AI.CHURN_SCORES cs ON c.customer_id = cs.customer_id
LEFT JOIN CORE.TICKETS t     ON c.customer_id = t.customer_id
GROUP BY c.org_id;

-- DT_CUSTOMER_HEALTH — perfil de saúde individual por cliente
CREATE OR REPLACE DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Saude e segmento por cliente — lag 1h'
AS
SELECT
    c.customer_id,
    c.org_id,
    c.name,
    c.email,
    c.segment,
    c.region,
    c.industry,
    c.arr,
    c.mrr,
    c.nps_score,
    c.lifecycle_stage,
    c.contract_end_date,
    COALESCE(cs.churn_probability, 0.5)                              AS churn_risk_score,
    COALESCE(cs.risk_level, 'MEDIUM')                                AS risk_level,
    COALESCE(cs.recommended_action, 'Monitorar padrao de engajamento') AS recommended_action,
    CASE
        WHEN COALESCE(cs.churn_probability, 0.5) >= 0.7 THEN 'CRITICAL'
        WHEN COALESCE(cs.churn_probability, 0.5) >= 0.5 THEN 'AT_RISK'
        WHEN COALESCE(cs.churn_probability, 0.5) >= 0.3 THEN 'HEALTHY'
        ELSE 'CHAMPION'
    END                                                              AS health_segment,
    COUNT(DISTINCT t.ticket_id)                                      AS open_ticket_count,
    COUNT(DISTINCT i.interaction_id)                                 AS interaction_count_30d,
    CURRENT_TIMESTAMP()                                              AS refreshed_at
FROM CORE.CUSTOMERS c
LEFT JOIN AI.CHURN_SCORES cs
    ON c.customer_id = cs.customer_id
LEFT JOIN CORE.TICKETS t
    ON c.customer_id = t.customer_id AND t.status = 'open'
LEFT JOIN CORE.INTERACTIONS i
    ON c.customer_id = i.customer_id
    AND i.occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY
    c.customer_id, c.org_id, c.name, c.email, c.segment, c.region, c.industry,
    c.arr, c.mrr, c.nps_score, c.lifecycle_stage, c.contract_end_date,
    cs.churn_probability, cs.risk_level, cs.recommended_action;

-- DT_REVENUE_MOVEMENT — movimento de receita mensal (New/Expansion/Churn)
CREATE OR REPLACE DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_COMPUTE_WH
    COMMENT    = 'Movimento de receita por mes e tipo de transacao'
AS
SELECT
    org_id,
    DATE_TRUNC('month', transaction_date)   AS month,
    transaction_type,
    COUNT(*)                                AS transaction_count,
    SUM(amount)                             AS total_amount,
    ROUND(AVG(amount), 2)                   AS avg_amount,
    MIN(amount)                             AS min_amount,
    MAX(amount)                             AS max_amount
FROM CORE.TRANSACTIONS
WHERE transaction_date IS NOT NULL
GROUP BY org_id, DATE_TRUNC('month', transaction_date), transaction_type;

-- GRANTs para Dynamic Tables
GRANT SELECT ON DYNAMIC TABLE MART.DT_EXECUTIVE_KPIS  TO ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE MART.DT_CUSTOMER_HEALTH TO ROLE NEXUS_VIEWER;
GRANT SELECT ON DYNAMIC TABLE MART.DT_REVENUE_MOVEMENT TO ROLE NEXUS_VIEWER;
