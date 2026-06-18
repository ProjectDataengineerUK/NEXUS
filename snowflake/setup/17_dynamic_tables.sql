-- NEXUS AI DataOps — Dynamic Tables
-- Refresh automático das camadas MART e AI sem necessidade de Tasks/dbt schedule.
-- TARGET_LAG define a latência máxima aceitável para cada tabela.
-- Executa APÓS o dbt ter criado as tabelas base (pode coexistir ou substituir).

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;

-- ─────────────────────────────────────────────────────────────────────────────
-- DT 1: MART.EXECUTIVE_KPIS_RT — snapshot near-real-time (2h lag)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE MART.EXECUTIVE_KPIS_RT
    TARGET_LAG     = '2 hours'
    WAREHOUSE      = NEXUS_COMPUTE_WH
    COMMENT        = 'KPIs executivos com refresh automático a cada 2h'
AS
WITH churn_scores AS (
    SELECT customer_id, org_id, risk_level, expected_revenue_at_risk
    FROM AI.CHURN_SCORES
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY scored_at DESC) = 1
),
recommendations AS (
    SELECT org_id,
           COUNT(*)                 AS cnt,
           SUM(expected_impact_usd) AS total_impact
    FROM AI.RECOMMENDATIONS
    WHERE status = 'pending' AND is_active = TRUE
    GROUP BY 1
),
tickets AS (
    SELECT org_id,
           COUNT_IF(status = 'open')                          AS open_tickets,
           COUNT_IF(status = 'open' AND priority = 'urgent')  AS urgent_tickets
    FROM CORE.TICKETS
    GROUP BY 1
),
customers AS (
    SELECT * FROM MART.CUSTOMER_360
)
SELECT
    c.org_id,
    CURRENT_DATE()                                                             AS snapshot_date,
    SUM(CASE WHEN c.lifecycle_stage != 'churned' THEN c.arr  ELSE 0 END)      AS total_arr,
    SUM(CASE WHEN c.lifecycle_stage != 'churned' THEN c.mrr  ELSE 0 END)      AS total_mrr,
    COUNT_IF(c.lifecycle_stage = 'active')                                     AS active_customers,
    COUNT_IF(c.lifecycle_stage = 'at_risk')                                    AS at_risk_customers,
    COUNT_IF(c.lifecycle_stage = 'churned')                                    AS churned_customers,
    COUNT(*)                                                                   AS total_customers,
    ROUND(AVG(CASE WHEN c.lifecycle_stage != 'churned' THEN c.health_score END), 1) AS avg_health_score,
    ROUND(AVG(CASE WHEN c.lifecycle_stage != 'churned' THEN c.nps_score    END), 1) AS avg_nps,
    SUM(CASE WHEN cs.risk_level IN ('HIGH','MEDIUM')
             THEN COALESCE(cs.expected_revenue_at_risk, 0) ELSE 0 END)        AS arr_at_risk,
    SUM(CASE
        WHEN c.lifecycle_stage IN ('active','at_risk')
         AND c.nearest_renewal_date <= DATEADD('day', 90, CURRENT_DATE())
        THEN c.arr ELSE 0
    END)                                                                       AS renewals_90d_arr,
    COALESCE(MAX(t.open_tickets),   0)                                        AS open_tickets,
    COALESCE(MAX(t.urgent_tickets), 0)                                        AS urgent_tickets,
    COALESCE(MAX(r.cnt),            0)                                        AS pending_recommendations,
    COALESCE(MAX(r.total_impact),   0)                                        AS total_expected_impact,
    CURRENT_TIMESTAMP()                                                       AS refreshed_at
FROM customers c
LEFT JOIN churn_scores   cs ON c.customer_id = cs.customer_id AND c.org_id = cs.org_id
LEFT JOIN tickets         t ON c.org_id = t.org_id
LEFT JOIN recommendations r ON c.org_id = r.org_id
GROUP BY c.org_id;

-- ─────────────────────────────────────────────────────────────────────────────
-- DT 2: MART.REVENUE_DAILY_RT — movimentos de receita (1h lag)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE MART.REVENUE_DAILY_RT
    TARGET_LAG     = '1 hour'
    WAREHOUSE      = NEXUS_COMPUTE_WH
    COMMENT        = 'Métricas de receita diária com refresh automático a cada 1h'
AS
WITH transactions AS (
    SELECT
        org_id,
        transaction_date                                                          AS revenue_date,
        SUM(CASE WHEN transaction_type = 'new_contract' THEN amount/12 ELSE 0 END) AS new_mrr,
        SUM(CASE WHEN transaction_type = 'upsell'       THEN amount/12 ELSE 0 END) AS expansion_mrr,
        SUM(CASE WHEN transaction_type = 'downgrade'    THEN amount/12 ELSE 0 END) AS contraction_mrr,
        SUM(CASE WHEN transaction_type = 'churn'        THEN amount/12 ELSE 0 END) AS churn_mrr,
        SUM(CASE WHEN transaction_type = 'renewal'      THEN amount/12 ELSE 0 END) AS renewal_mrr,
        SUM(amount)                                                            AS total_revenue_booked,
        COUNT(DISTINCT transaction_id)                                             AS transaction_count,
        COUNT(DISTINCT customer_id)                                                AS customers_transacted
    FROM CORE.TRANSACTIONS
    GROUP BY 1, 2
)
SELECT
    org_id,
    revenue_date,
    new_mrr,
    expansion_mrr,
    contraction_mrr,
    churn_mrr,
    renewal_mrr,
    total_revenue_booked,
    transaction_count,
    customers_transacted,
    new_mrr + expansion_mrr - contraction_mrr - churn_mrr          AS net_new_mrr,
    (new_mrr + expansion_mrr - contraction_mrr - churn_mrr) * 12   AS net_new_arr,
    CURRENT_TIMESTAMP()                                              AS refreshed_at
FROM transactions;

-- ─────────────────────────────────────────────────────────────────────────────
-- DT 3: AI.CHURN_FEATURES_RT — feature store para ML (30min lag)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE AI.CHURN_FEATURES_RT
    TARGET_LAG     = '30 minutes'
    WAREHOUSE      = NEXUS_ML_WH
    COMMENT        = 'Feature store de churn para inferência Snowpark ML (30min lag)'
AS
WITH base AS (
    SELECT
        c.customer_id,
        c.org_id,
        c.segment,
        c.region,
        c.industry,
        c.lifecycle_stage,
        COALESCE(c.health_score,           50)  AS health_score,
        COALESCE(c.nps_score,               0)  AS nps_score,
        COALESCE(c.churn_probability,     0.1)  AS churn_probability,
        COALESCE(c.events_30d,              0)  AS events_30d,
        COALESCE(c.active_days_30d,         0)  AS active_days_30d,
        COALESCE(c.days_since_last_activity,999) AS days_since_last_activity,
        COALESCE(c.open_tickets,            0)  AS open_tickets,
        COALESCE(c.sla_breaches,            0)  AS sla_breaches,
        COALESCE(c.mrr,                     0)  AS mrr,
        COALESCE(c.arr,                     0)  AS arr,
        COALESCE(c.total_seats,             0)  AS total_seats,
        COALESCE(c.events_7d,               0)  AS events_7d,
        COALESCE(c.features_used,           0)  AS features_used,
        COALESCE(c.sla_breaches_30d,        0)  AS sla_breaches_30d,
        COALESCE(c.tickets_30d,             0)  AS tickets_30d,
        COALESCE(c.ai_invocations_30d,      0)  AS ai_invocations_30d,
        c.usage_trend,
        c.churn_risk_level,
        COALESCE(c.days_to_renewal,       365)  AS days_to_renewal,
        CASE WHEN c.lifecycle_stage = 'churned' THEN 1 ELSE 0 END AS is_churned
    FROM MART.CUSTOMER_360 c
)
SELECT
    *,
    CASE WHEN total_seats > 0
         THEN ROUND(open_tickets * 1.0 / total_seats, 3)
         ELSE 0
    END                                                              AS tickets_per_seat,
    CASE WHEN events_30d > 0
         THEN ROUND((events_7d * 4.3) / events_30d, 2)
         ELSE 1.0
    END                                                              AS usage_velocity_ratio,
    ROUND(
        (  LEAST(active_days_30d / 20.0, 1.0) * 0.5
         + LEAST(events_30d      / 500.0, 1.0) * 0.3
         + LEAST(features_used   / 10.0,  1.0) * 0.2 ), 3
    )                                                                AS engagement_score,
    CURRENT_TIMESTAMP()                                              AS refreshed_at
FROM base;

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants de acesso às Dynamic Tables
-- ─────────────────────────────────────────────────────────────────────────────

GRANT SELECT ON TABLE MART.EXECUTIVE_KPIS_RT  TO ROLE NEXUS_ANALYST;
GRANT SELECT ON TABLE MART.EXECUTIVE_KPIS_RT  TO ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE MART.REVENUE_DAILY_RT   TO ROLE NEXUS_ANALYST;
GRANT SELECT ON TABLE MART.REVENUE_DAILY_RT   TO ROLE NEXUS_VIEWER;
GRANT SELECT ON TABLE AI.CHURN_FEATURES_RT    TO ROLE NEXUS_ANALYST;
