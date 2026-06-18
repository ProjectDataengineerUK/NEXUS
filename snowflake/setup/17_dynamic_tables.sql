-- ─────────────────────────────────────────────────────────────────────────────
-- NEXUS AI DataOps — Dynamic Tables (deploy direto, fora do Native App)
-- Arquivo: 17_dynamic_tables.sql
--
-- Finalidade: refresh automático das camadas MART e AI sem Tasks manuais
-- nem schedule dbt. O mecanismo de refresh é declarativo — o Snowflake
-- recalcula cada DT assim que o TARGET_LAG máximo for atingido.
--
-- Pre-requisitos:
--   - 04_core_tables.sql  executado (CORE.CUSTOMERS, TICKETS, PRODUCT_EVENTS,
--                                    TRANSACTIONS, SUBSCRIPTIONS)
--   - 05_ai_tables.sql    executado (AI.CHURN_SCORES, AI.RECOMMENDATIONS)
--   - 12_customer_360_sprint2.sql executado (MART.CUSTOMER_360 como DT base)
--   - Warehouse NEXUS_COMPUTE_WH provisionado
--   - Roles NEXUS_ADMIN e NEXUS_ANALYST existentes
--
-- Ordem de criação importa — DTs que dependem de outra DT devem vir depois:
--   1. MART.DT_CUSTOMER_HEALTH      (depende de CORE.* e AI.*)
--   2. MART.DT_EXECUTIVE_KPIS       (depende de MART.DT_CUSTOMER_HEALTH)
--   3. MART.DT_REVENUE_MOVEMENT     (depende de CORE.TRANSACTIONS)
--   4. AI.DT_SUPPORT_INTELLIGENCE   (depende de CORE.TICKETS)
-- ─────────────────────────────────────────────────────────────────────────────

USE ROLE NEXUS_ADMIN;
USE DATABASE NEXUS_APP;


-- ─────────────────────────────────────────────────────────────────────────────
-- DT 1: MART.DT_CUSTOMER_HEALTH
--
-- TARGET_LAG = '1 hour': equilíbrio entre frescor e custo de compute.
-- Churn scores são re-inferidos no máximo a cada hora pelo pipeline ML,
-- portanto latência sub-hora nesta DT não traria ganho real.
-- É a DT mais cara (JOIN de 5 tabelas) — warehouse XS é suficiente para
-- volumes até ~5M clientes/org; escalar para S se P99 de refresh > 50 min.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH
    TARGET_LAG  = '1 hour'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
    COMMENT     = 'Saúde consolidada por cliente: churn score, tickets abertos, uso 30d e health_score derivado. Refresh a cada 1h.'
AS
WITH

-- Último churn score por cliente (QUALIFY elimina subquery de rn)
latest_churn AS (
    SELECT
        customer_id,
        org_id,
        churn_probability,
        risk_level,
        expected_revenue_at_risk,
        recommended_action,
        scored_at
    FROM NEXUS_APP.AI.CHURN_SCORES
    QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id, org_id ORDER BY scored_at DESC) = 1
),

-- Tickets abertos por cliente
open_ticket_counts AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                                         AS open_tickets,
        COUNT(CASE WHEN priority IN ('urgent', 'high') THEN 1 END)      AS critical_open_tickets,
        COUNT(CASE WHEN sla_breach = TRUE THEN 1 END)                   AS sla_breaches
    FROM NEXUS_APP.CORE.TICKETS
    WHERE status = 'open'
    GROUP BY customer_id, org_id
),

-- Eventos de produto nos últimos 30 dias
usage_30d AS (
    SELECT
        customer_id,
        org_id,
        COUNT(*)                                   AS events_30d,
        COUNT(DISTINCT DATE(occurred_at))          AS active_days_30d,
        COUNT(DISTINCT feature_name)               AS distinct_features_30d,
        MAX(occurred_at)                           AS last_activity_at
    FROM NEXUS_APP.CORE.PRODUCT_EVENTS
    WHERE occurred_at >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY customer_id, org_id
)

SELECT
    -- Identificação
    c.customer_id,
    c.org_id,
    c.name                                                              AS customer_name,
    c.segment,
    c.lifecycle_stage,

    -- Receita (preferência para assinatura ativa; fallback para campo do cliente)
    c.arr,
    c.mrr,
    c.nps_score,

    -- Renewal
    c.contract_end_date                                                 AS contract_end_date,
    DATEDIFF('day', CURRENT_DATE(), c.contract_end_date)               AS days_to_renewal,

    -- Churn AI
    COALESCE(cs.churn_probability, 0.5)                                AS churn_probability,
    COALESCE(cs.risk_level, 'UNKNOWN')                                 AS churn_risk_level,
    COALESCE(cs.expected_revenue_at_risk, 0)                           AS expected_revenue_at_risk,
    cs.recommended_action                                               AS churn_recommended_action,
    cs.scored_at                                                        AS churn_scored_at,

    -- Tickets
    COALESCE(t.open_tickets,          0)                               AS open_tickets,
    COALESCE(t.critical_open_tickets, 0)                               AS critical_open_tickets,
    COALESCE(t.sla_breaches,          0)                               AS sla_breaches,

    -- Uso
    COALESCE(u.events_30d,            0)                               AS events_30d,
    COALESCE(u.active_days_30d,       0)                               AS active_days_30d,
    COALESCE(u.distinct_features_30d, 0)                               AS distinct_features_30d,
    u.last_activity_at,
    DATEDIFF('day', u.last_activity_at, CURRENT_TIMESTAMP())           AS days_since_last_activity,

    -- Health Score derivado (0–100)
    -- Fórmula: complemento da churn probability normalizado para 0–100.
    -- Simples e determinístico — não requer modelo separado.
    ROUND((1 - COALESCE(cs.churn_probability, 0.5)) * 100, 0)         AS health_score,

    CURRENT_TIMESTAMP()                                                 AS refreshed_at

FROM NEXUS_APP.CORE.CUSTOMERS        c
LEFT JOIN latest_churn       cs ON c.customer_id = cs.customer_id AND c.org_id = cs.org_id
LEFT JOIN open_ticket_counts  t ON c.customer_id = t.customer_id  AND c.org_id = t.org_id
LEFT JOIN usage_30d           u ON c.customer_id = u.customer_id  AND c.org_id = u.org_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- DT 2: MART.DT_EXECUTIVE_KPIS
--
-- TARGET_LAG = '1 hour': KPIs executivos são consultados em dashboards com
-- atualização horária — latência menor aumentaria custo sem valor perceptível.
-- Depende de DT_CUSTOMER_HEALTH (criada acima) para herdar health_score e
-- churn_risk_level já calculados, evitando recomputar os JOINs de AI.*.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS
    TARGET_LAG  = '1 hour'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
    COMMENT     = 'Snapshot executivo por org: ARR, MRR, contagem de clientes, NPS, ARR em risco, renovações 90d e recomendações ativas. Refresh a cada 1h.'
AS
WITH

-- Agrega recomendações ativas por org
active_recommendations AS (
    SELECT
        org_id,
        COUNT(*)                    AS open_recommendations,
        SUM(expected_impact_usd)    AS total_expected_impact_usd
    FROM NEXUS_APP.AI.RECOMMENDATIONS
    WHERE is_active = TRUE
      AND status    = 'pending'
    GROUP BY org_id
)

SELECT
    h.org_id,

    -- Volume de clientes
    COUNT(*)                                                            AS customer_count,
    COUNT(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled') THEN 1 END) AS active_count,
    COUNT(CASE WHEN h.churn_risk_level = 'HIGH' THEN 1 END)            AS at_risk_count,
    COUNT(CASE WHEN h.lifecycle_stage IN ('churned', 'cancelled') THEN 1 END) AS churned_count,

    -- Receita consolidada (apenas clientes não churned)
    SUM(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
             THEN COALESCE(h.arr, 0) ELSE 0 END)                       AS total_arr,
    SUM(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
             THEN COALESCE(h.mrr, 0) ELSE 0 END)                       AS total_mrr,

    -- NPS médio (exclui churned e NULLs)
    ROUND(AVG(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
                   THEN h.nps_score END), 1)                            AS avg_nps,

    -- ARR em risco: HIGH ou MEDIUM churn risk
    SUM(CASE WHEN h.churn_risk_level IN ('HIGH', 'MEDIUM')
             THEN COALESCE(h.expected_revenue_at_risk, 0) ELSE 0 END)  AS arr_at_risk,

    -- ARR de clientes com renovação nos próximos 90 dias
    SUM(CASE
        WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
         AND h.contract_end_date IS NOT NULL
         AND h.days_to_renewal BETWEEN 0 AND 90
        THEN COALESCE(h.arr, 0) ELSE 0
    END)                                                                AS renewal_90d_arr,

    -- Recomendações pendentes
    COALESCE(r.open_recommendations,       0)                          AS open_recommendations,
    COALESCE(r.total_expected_impact_usd,  0)                          AS total_expected_impact_usd,

    -- Health médio da base ativa
    ROUND(AVG(CASE WHEN h.lifecycle_stage NOT IN ('churned', 'cancelled')
                   THEN h.health_score END), 1)                         AS avg_health_score,

    CURRENT_TIMESTAMP()                                                 AS refreshed_at

FROM NEXUS_APP.MART.DT_CUSTOMER_HEALTH      h
LEFT JOIN active_recommendations             r ON h.org_id = r.org_id
GROUP BY h.org_id, r.open_recommendations, r.total_expected_impact_usd;


-- ─────────────────────────────────────────────────────────────────────────────
-- DT 3: MART.DT_REVENUE_MOVEMENT
--
-- TARGET_LAG = '1 day': movimentos de MRR/ARR são eventos contábeis —
-- granularidade diária é o máximo necessário para waterfall charts e
-- análises de net revenue retention. Usar lag menor elevaria custo
-- sem ganho analítico (CORE.TRANSACTIONS raramente tem granularidade
-- intra-diária para ARR/MRR).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT
    TARGET_LAG  = '1 day'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
    COMMENT     = 'Movimento de MRR/ARR por dia e tipo de transação (new, expansion, contraction, churn, renewal). Base para waterfall de ARR. Refresh diário.'
AS
SELECT
    org_id,
    transaction_date                                                    AS revenue_date,

    -- Novos contratos (ARR novo entrante)
    SUM(CASE WHEN transaction_type = 'new_contract'
             THEN COALESCE(amount, 0) ELSE 0 END)                      AS new_arr,
    SUM(CASE WHEN transaction_type = 'new_contract'
             THEN COALESCE(amount, 0) / 12.0 ELSE 0 END)               AS new_mrr,

    -- Expansão (upsell / add-on)
    SUM(CASE WHEN transaction_type = 'upsell'
             THEN COALESCE(amount, 0) ELSE 0 END)                      AS expansion_arr,
    SUM(CASE WHEN transaction_type = 'upsell'
             THEN COALESCE(amount, 0) / 12.0 ELSE 0 END)               AS expansion_mrr,

    -- Contração (downgrade)
    SUM(CASE WHEN transaction_type = 'downgrade'
             THEN COALESCE(amount, 0) ELSE 0 END)                      AS contraction_arr,
    SUM(CASE WHEN transaction_type = 'downgrade'
             THEN COALESCE(amount, 0) / 12.0 ELSE 0 END)               AS contraction_mrr,

    -- Churn (cancelamento definitivo)
    SUM(CASE WHEN transaction_type = 'churn'
             THEN COALESCE(amount, 0) ELSE 0 END)                      AS churn_arr,
    SUM(CASE WHEN transaction_type = 'churn'
             THEN COALESCE(amount, 0) / 12.0 ELSE 0 END)               AS churn_mrr,

    -- Renovação (sem mudança de valor)
    SUM(CASE WHEN transaction_type = 'renewal'
             THEN COALESCE(amount, 0) ELSE 0 END)                      AS renewal_arr,
    SUM(CASE WHEN transaction_type = 'renewal'
             THEN COALESCE(amount, 0) / 12.0 ELSE 0 END)               AS renewal_mrr,

    -- Net ARR = new + expansion - contraction - churn
    (  SUM(CASE WHEN transaction_type = 'new_contract' THEN COALESCE(amount, 0) ELSE 0 END)
     + SUM(CASE WHEN transaction_type = 'upsell'       THEN COALESCE(amount, 0) ELSE 0 END)
     - SUM(CASE WHEN transaction_type = 'downgrade'    THEN COALESCE(amount, 0) ELSE 0 END)
     - SUM(CASE WHEN transaction_type = 'churn'        THEN COALESCE(amount, 0) ELSE 0 END)
    )                                                                   AS net_arr,

    -- Net MRR equivalente
    (  SUM(CASE WHEN transaction_type = 'new_contract' THEN COALESCE(amount, 0) ELSE 0 END)
     + SUM(CASE WHEN transaction_type = 'upsell'       THEN COALESCE(amount, 0) ELSE 0 END)
     - SUM(CASE WHEN transaction_type = 'downgrade'    THEN COALESCE(amount, 0) ELSE 0 END)
     - SUM(CASE WHEN transaction_type = 'churn'        THEN COALESCE(amount, 0) ELSE 0 END)
    ) / 12.0                                                            AS net_mrr,

    -- Volume
    COUNT(DISTINCT transaction_id)                                      AS transaction_count,
    COUNT(DISTINCT customer_id)                                         AS customers_transacted,

    -- Total bookings (todas as transações, incluindo renovação)
    SUM(COALESCE(amount, 0))                                            AS total_revenue_booked,

    CURRENT_TIMESTAMP()                                                 AS refreshed_at

FROM NEXUS_APP.CORE.TRANSACTIONS
WHERE status = 'completed'
GROUP BY org_id, transaction_date;


-- ─────────────────────────────────────────────────────────────────────────────
-- DT 4: AI.DT_SUPPORT_INTELLIGENCE
--
-- TARGET_LAG = '30 minutes': suporte ao cliente exige reatividade mais alta
-- do que KPIs executivos. Um ticket crítico aberto há 30 min já é
-- acionável — lag de 1h criaria ponto cego operacional.
-- Depende apenas de CORE.TICKETS (tabela base, sem DTs intermediárias)
-- logo não há risco de propagação de lag em cascata.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE
    TARGET_LAG  = '30 minutes'
    WAREHOUSE   = NEXUS_COMPUTE_WH
    INITIALIZE  = ON_CREATE
    COMMENT     = 'Inteligência de suporte por org: tickets abertos, SLA, resolução média, sentimento e tendência 7d. Refresh a cada 30 min.'
AS
SELECT
    org_id,

    -- Volume geral
    COUNT(*)                                                            AS total_tickets,
    COUNT(CASE WHEN status = 'open' THEN 1 END)                        AS open_tickets,
    COUNT(CASE WHEN status = 'resolved' THEN 1 END)                    AS resolved_tickets,

    -- Criticidade
    COUNT(CASE WHEN status = 'open'
               AND priority IN ('urgent', 'high') THEN 1 END)          AS critical_tickets,

    -- SLA
    COUNT(CASE WHEN sla_breach = TRUE THEN 1 END)                      AS sla_breached_count,
    ROUND(
        COUNT(CASE WHEN sla_breach = TRUE THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 2
    )                                                                   AS sla_breach_rate_pct,

    -- Tempo médio de resolução em horas (apenas tickets fechados)
    ROUND(
        AVG(CASE WHEN resolved_at IS NOT NULL
                 THEN DATEDIFF('minute', created_at, resolved_at) / 60.0
            END), 2
    )                                                                   AS avg_resolution_hours,

    -- Menor tempo de resolução (melhor caso) e maior (pior caso)
    ROUND(
        MIN(CASE WHEN resolved_at IS NOT NULL
                 THEN DATEDIFF('minute', created_at, resolved_at) / 60.0
            END), 2
    )                                                                   AS min_resolution_hours,
    ROUND(
        MAX(CASE WHEN resolved_at IS NOT NULL
                 THEN DATEDIFF('minute', created_at, resolved_at) / 60.0
            END), 2
    )                                                                   AS max_resolution_hours,

    -- Sentimento médio nos tickets abertos (reflete estado atual do cliente)
    ROUND(AVG(CASE WHEN status = 'open' THEN sentiment_score END), 3)  AS avg_open_sentiment,

    -- Sentimento médio geral (todos os tickets do período)
    ROUND(AVG(sentiment_score), 3)                                      AS avg_sentiment,

    -- Distribuição de sentimento
    COUNT(CASE WHEN sentiment_label = 'positive' THEN 1 END)           AS positive_tickets,
    COUNT(CASE WHEN sentiment_label = 'neutral'  THEN 1 END)           AS neutral_tickets,
    COUNT(CASE WHEN sentiment_label = 'negative' THEN 1 END)           AS negative_tickets,

    -- Tendência: tickets abertos nos últimos 7 dias
    COUNT(CASE WHEN created_at >= DATEADD('day', -7, CURRENT_TIMESTAMP())
               THEN 1 END)                                              AS tickets_trend_7d,

    -- Tickets abertos há mais de 48h (risco de SLA iminente)
    COUNT(CASE WHEN status = 'open'
               AND DATEDIFF('hour', created_at, CURRENT_TIMESTAMP()) > 48
               THEN 1 END)                                              AS stale_open_tickets,

    -- Data do ticket mais antigo ainda aberto
    MIN(CASE WHEN status = 'open' THEN created_at END)                 AS oldest_open_ticket_at,

    CURRENT_TIMESTAMP()                                                 AS refreshed_at

FROM NEXUS_APP.CORE.TICKETS
GROUP BY org_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- GRANTs
-- Contexto: deploy direto (fora do Native App).
-- NEXUS_ANALYST: acesso analítico completo às DTs (leitura).
-- NEXUS_ADMIN:   já tem OWNERSHIP implícito por ter criado as DTs,
--                mas o GRANT explícito garante portabilidade se a role
--                owner mudar no futuro.
-- ─────────────────────────────────────────────────────────────────────────────

-- DT_CUSTOMER_HEALTH
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH      TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH      TO ROLE NEXUS_ADMIN;

-- DT_EXECUTIVE_KPIS
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS       TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS       TO ROLE NEXUS_ADMIN;

-- DT_REVENUE_MOVEMENT
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT     TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT     TO ROLE NEXUS_ADMIN;

-- DT_SUPPORT_INTELLIGENCE
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE   TO ROLE NEXUS_ANALYST;
GRANT SELECT ON DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE   TO ROLE NEXUS_ADMIN;


-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDAÇÃO PÓS-DEPLOY (executar manualmente após criar as DTs)
-- ─────────────────────────────────────────────────────────────────────────────

/*

-- 1. Verificar status de refresh de todas as DTs deste arquivo
SHOW DYNAMIC TABLES LIKE 'DT_%' IN DATABASE NEXUS_APP;

-- 2. Status detalhado individual
SELECT
    name,
    schema_name,
    target_lag,
    warehouse,
    refresh_mode,
    scheduling_state,
    last_suspended_on,
    comment
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY schema_name, name;

-- 3. Histórico de refreshes (últimas 24h) — via Information Schema
SELECT
    name,
    state,
    state_message,
    query_start_time,
    DATEDIFF('second', query_start_time, completed_time) AS duration_sec,
    completed_time
FROM TABLE(NEXUS_APP.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    DATE_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP()),
    DATE_RANGE_END   => CURRENT_TIMESTAMP()
))
WHERE name ILIKE 'DT_%'
ORDER BY query_start_time DESC;

-- 4. Sanidade: DT_CUSTOMER_HEALTH deve ter 1 linha por customer_id
SELECT COUNT(*) AS total_customers, COUNT(DISTINCT customer_id) AS distinct_ids
FROM NEXUS_APP.MART.DT_CUSTOMER_HEALTH;

-- 5. Sanidade: DT_EXECUTIVE_KPIS deve ter 1 linha por org_id
SELECT org_id, customer_count, total_arr, arr_at_risk, avg_health_score
FROM NEXUS_APP.MART.DT_EXECUTIVE_KPIS
ORDER BY total_arr DESC;

-- 6. Sanidade: DT_REVENUE_MOVEMENT — últimos 7 dias devem ter dados se houver transações
SELECT revenue_date, org_id, new_arr, expansion_arr, churn_arr, net_arr
FROM NEXUS_APP.MART.DT_REVENUE_MOVEMENT
WHERE revenue_date >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY revenue_date DESC, net_arr DESC;

-- 7. Sanidade: DT_SUPPORT_INTELLIGENCE — critical_tickets e sla_breach_rate_pct
SELECT org_id, open_tickets, critical_tickets, sla_breach_rate_pct,
       avg_resolution_hours, tickets_trend_7d, avg_sentiment
FROM NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE
ORDER BY critical_tickets DESC;

-- 8. Forçar refresh manual se necessário (não aguarda TARGET_LAG)
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH    REFRESH;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS     REFRESH;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT   REFRESH;
-- ALTER DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE REFRESH;

-- 9. Suspender DTs em ambiente de desenvolvimento para não consumir créditos
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH    SUSPEND;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS     SUSPEND;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT   SUSPEND;
-- ALTER DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE SUSPEND;

-- 10. Reativar
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_CUSTOMER_HEALTH    RESUME;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_EXECUTIVE_KPIS     RESUME;
-- ALTER DYNAMIC TABLE NEXUS_APP.MART.DT_REVENUE_MOVEMENT   RESUME;
-- ALTER DYNAMIC TABLE NEXUS_APP.AI.DT_SUPPORT_INTELLIGENCE RESUME;

*/
