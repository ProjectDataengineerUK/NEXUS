-- NEXUS AI DataOps — Sprint 2: Customer 360 Dynamic Table
-- Agrega CUSTOMERS, SUBSCRIPTIONS, TICKETS, PRODUCT_EVENTS, CONTRACTS, CHURN_SCORES
-- em uma visão consolidada por cliente, atualizada a cada hora.

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;
USE WAREHOUSE NEXUS_ORCHESTRATION_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- MART.CUSTOMER_360
-- Visão única por cliente com todas as métricas de negócio calculadas.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.CUSTOMER_360
    TARGET_LAG = '1 hour'
    WAREHOUSE  = NEXUS_ORCHESTRATION_WH
    COMMENT    = 'Sprint 2 — Customer 360: métricas consolidadas por cliente'
AS
WITH

-- Última pontuação de churn por cliente
latest_churn AS (
    SELECT
        customer_id,
        org_id,
        churn_probability,
        risk_level,
        recommended_action,
        expected_revenue_at_risk,
        scored_at,
        ROW_NUMBER() OVER (PARTITION BY customer_id, org_id ORDER BY scored_at DESC) AS rn
    FROM NEXUS_APP.AI.CHURN_SCORES
),

-- Métricas de tickets
ticket_metrics AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                    AS total_tickets,
        COUNT(CASE WHEN status = 'open'  THEN 1 END)               AS open_tickets,
        COUNT(CASE WHEN priority IN ('urgent','high') AND status = 'open' THEN 1 END) AS critical_open_tickets,
        COUNT(CASE WHEN sla_breach = TRUE THEN 1 END)              AS sla_breaches,
        ROUND(AVG(sentiment_score), 3)                             AS avg_sentiment_score,
        MAX(CASE WHEN sentiment_score < -0.5 THEN 1 ELSE 0 END)    AS has_critical_negative,
        MAX(created_at)                                            AS last_ticket_date
    FROM NEXUS_APP.CORE.TICKETS
    GROUP BY customer_id, org_id
),

-- Métricas de uso (últimos 30 dias)
usage_30d AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                    AS events_30d,
        COUNT(DISTINCT DATE(occurred_at))                          AS active_days_30d,
        COUNT(DISTINCT feature_name)                               AS distinct_features_used,
        COUNT(CASE WHEN event_type = 'agent_invoked' THEN 1 END)   AS agent_invocations_30d,
        MAX(occurred_at)                                           AS last_activity_at
    FROM NEXUS_APP.CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
),

-- Métricas de uso (últimos 7 dias — para trend)
usage_7d AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                    AS events_7d,
        COUNT(DISTINCT DATE(occurred_at))                          AS active_days_7d
    FROM NEXUS_APP.CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
),

-- Subscrições ativas
sub_metrics AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                    AS active_subscriptions,
        SUM(mrr)                                                    AS total_mrr,
        SUM(arr)                                                    AS total_arr,
        SUM(seats)                                                  AS total_seats,
        MIN(current_period_end)                                     AS nearest_renewal_date,
        LISTAGG(plan_name, ' | ') WITHIN GROUP (ORDER BY arr DESC)  AS plan_names
    FROM NEXUS_APP.CORE.SUBSCRIPTIONS
    WHERE status = 'active'
    GROUP BY customer_id, org_id
),

-- Contratos (mais recente ativo)
contract_metrics AS (
    SELECT
        customer_id,
        org_id,
        MAX(contract_value)                                         AS highest_contract_value,
        MIN(end_date)                                               AS nearest_contract_end,
        COUNT(CASE WHEN status = 'active' THEN 1 END)               AS active_contracts,
        BOOLOR_AGG(auto_renewal)                                    AS has_auto_renewal
    FROM NEXUS_APP.CORE.CONTRACTS
    GROUP BY customer_id, org_id
)

SELECT
    -- Identificação
    c.customer_id,
    c.org_id,
    c.name                                                         AS customer_name,
    c.email,
    c.segment,
    c.region,
    c.industry,
    c.lifecycle_stage,
    c.source_system,

    -- Revenue
    COALESCE(s.total_arr,  c.arr)                                  AS arr,
    COALESCE(s.total_mrr,  c.mrr)                                  AS mrr,
    s.total_seats,
    s.active_subscriptions,
    s.plan_names,
    s.nearest_renewal_date,

    -- Churn & Saúde
    cs.churn_probability,
    cs.risk_level                                                  AS churn_risk_level,
    cs.recommended_action                                          AS churn_recommended_action,
    cs.expected_revenue_at_risk,
    cs.scored_at                                                   AS churn_scored_at,

    -- Health Score (0-100): pesos balanceados
    LEAST(100, GREATEST(0, ROUND(
          (1 - COALESCE(cs.churn_probability, 0.5))  * 35   -- 35% churn
        + CASE WHEN c.nps_score IS NULL THEN 15
               WHEN c.nps_score >= 70 THEN 30
               WHEN c.nps_score >= 50 THEN 20
               WHEN c.nps_score >= 30 THEN 10
               ELSE 5
          END                                                -- 30% NPS
        + LEAST(25, COALESCE(u30.active_days_30d, 0) * 1.0) -- 25% uso
        + CASE WHEN COALESCE(t.sla_breaches, 0) = 0 THEN 10
               WHEN t.sla_breaches <= 1 THEN 5
               ELSE 0
          END                                                -- 10% SLA
    , 1))) AS health_score,

    -- NPS
    c.nps_score,

    -- Tickets
    COALESCE(t.total_tickets, 0)                                   AS total_tickets,
    COALESCE(t.open_tickets, 0)                                    AS open_tickets,
    COALESCE(t.critical_open_tickets, 0)                           AS critical_open_tickets,
    COALESCE(t.sla_breaches, 0)                                    AS sla_breaches,
    t.avg_sentiment_score,
    CASE
        WHEN t.avg_sentiment_score >= 0.3  THEN 'positive'
        WHEN t.avg_sentiment_score <= -0.3 THEN 'negative'
        ELSE 'neutral'
    END                                                            AS sentiment_label,
    t.last_ticket_date,

    -- Uso
    COALESCE(u30.events_30d, 0)                                    AS events_30d,
    COALESCE(u30.active_days_30d, 0)                               AS active_days_30d,
    COALESCE(u30.distinct_features_used, 0)                        AS distinct_features_used,
    COALESCE(u30.agent_invocations_30d, 0)                         AS agent_invocations_30d,
    u30.last_activity_at,
    COALESCE(u7.events_7d, 0)                                      AS events_7d,
    COALESCE(u7.active_days_7d, 0)                                 AS active_days_7d,
    DATEDIFF('day', u30.last_activity_at, CURRENT_TIMESTAMP())     AS days_since_last_activity,

    -- Trend de uso (7d vs média semanal dos 30d)
    CASE
        WHEN COALESCE(u30.events_30d, 0) = 0 THEN 'no_data'
        WHEN COALESCE(u7.events_7d, 0) >= (u30.events_30d / 4.0 * 1.2) THEN 'up'
        WHEN COALESCE(u7.events_7d, 0) <= (u30.events_30d / 4.0 * 0.8) THEN 'down'
        ELSE 'stable'
    END                                                            AS usage_trend,

    -- Contratos
    co.active_contracts,
    co.nearest_contract_end,
    co.has_auto_renewal,

    -- Datas de controle
    c.contract_start_date,
    c.contract_end_date,
    c.created_at                                                   AS customer_since,
    CURRENT_TIMESTAMP()                                            AS refreshed_at

FROM NEXUS_APP.CORE.CUSTOMERS c
LEFT JOIN sub_metrics      s   ON c.customer_id = s.customer_id  AND c.org_id = s.org_id
LEFT JOIN latest_churn     cs  ON c.customer_id = cs.customer_id AND c.org_id = cs.org_id AND cs.rn = 1
LEFT JOIN ticket_metrics   t   ON c.customer_id = t.customer_id  AND c.org_id = t.org_id
LEFT JOIN usage_30d        u30 ON c.customer_id = u30.customer_id AND c.org_id = u30.org_id
LEFT JOIN usage_7d         u7  ON c.customer_id = u7.customer_id  AND c.org_id = u7.org_id
LEFT JOIN contract_metrics co  ON c.customer_id = co.customer_id  AND c.org_id = co.org_id;

-- Grant de leitura para roles analíticas
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.CUSTOMER_360 TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.CUSTOMER_360 TO ROLE NEXUS_VIEWER;
