{{
    config(
        materialized='incremental',
        unique_key='customer_id',
        incremental_strategy='merge',
        merge_update_columns=[
            'health_score', 'churn_probability', 'churn_risk_level',
            'lifecycle_stage', 'mrr', 'arr', 'nps_score',
            'open_tickets', 'sla_breaches', 'events_30d', 'active_days_30d',
            'usage_trend', 'expected_revenue_at_risk', 'churn_recommended_action',
            'nearest_renewal_date', 'days_to_renewal', '_dbt_updated_at'
        ],
        tags=["mart", "customer_360", "gold"],
        post_hook=[
            "ALTER TABLE {{ this }} CLUSTER BY (org_id, churn_risk_level)",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_VIEWER"
        ]
    )
}}

with customers as (
    select * from {{ ref('stg_customers') }}
),

subs as (
    select * from {{ ref('int_customer_subscription_metrics') }}
),

tickets as (
    select * from {{ ref('int_customer_ticket_metrics') }}
),

usage as (
    select * from {{ ref('int_customer_usage_metrics') }}
),

churn_scores as (
    select
        customer_id,
        churn_probability,
        risk_level             as churn_risk_level,
        recommended_action     as churn_recommended_action,
        expected_revenue_at_risk,
        top_drivers            as churn_top_drivers
    from {{ source('nexus_ai', 'churn_scores') }}
    where org_id = '{{ var("org_id") }}'
    qualify row_number() over (partition by customer_id order by scored_at desc) = 1
),

-- Junta todas as camadas
joined as (
    select
        c.customer_id,
        c.org_id,
        c.customer_name,
        c.email,
        c.phone,
        c.segment,
        c.region,
        c.industry,
        c.status,
        c.lifecycle_stage,
        c.nps_score,
        c.customer_since,

        -- Subscrições
        coalesce(s.mrr, 0)                                    as mrr,
        coalesce(s.arr, 0)                                    as arr,
        coalesce(s.total_seats, 0)                            as total_seats,
        coalesce(s.active_subscriptions, 0)                   as active_subscriptions,
        s.nearest_renewal_date,
        s.days_to_renewal,
        s.primary_plan_tier,
        coalesce(s.is_enterprise, 0) = 1                      as is_enterprise,

        -- Tickets
        coalesce(t.open_tickets, 0)                           as open_tickets,
        coalesce(t.sla_breaches, 0)                           as sla_breaches,
        coalesce(t.avg_sentiment_score, 0)                    as avg_sentiment_score,
        coalesce(t.dominant_sentiment, 'neutral')             as sentiment_label,
        coalesce(t.tickets_30d, 0)                            as tickets_30d,
        coalesce(t.sla_breaches_30d, 0)                       as sla_breaches_30d,

        -- Uso
        coalesce(u.events_30d, 0)                             as events_30d,
        coalesce(u.events_7d, 0)                              as events_7d,
        coalesce(u.active_days_30d, 0)                        as active_days_30d,
        coalesce(u.features_used, 0)                          as features_used,
        coalesce(u.ai_invocations_30d, 0)                     as ai_invocations_30d,
        coalesce(u.days_since_last_activity, 999)             as days_since_last_activity,
        coalesce(u.usage_trend, 'no_data')                    as usage_trend,

        -- Churn (do modelo ML via AI schema)
        coalesce(ch.churn_probability, 0.1)                   as churn_probability,
        coalesce(ch.churn_risk_level, 'LOW')                  as churn_risk_level,
        ch.churn_recommended_action,
        coalesce(ch.expected_revenue_at_risk, 0)              as expected_revenue_at_risk,
        ch.churn_top_drivers

    from customers c
    left join subs    s  on c.customer_id = s.customer_id
    left join tickets t  on c.customer_id = t.customer_id
    left join usage   u  on c.customer_id = u.customer_id
    left join churn_scores ch on c.customer_id = ch.customer_id
),

-- Calcula health score e lifecycle derivados
scored as (
    select
        *,

        -- NPS normalizado 0-100
        round((coalesce(nps_score, 0) + 100) / 2.0, 1)       as nps_normalized,

        -- Pontos de uso (0-100)
        case
            when active_days_30d >= 20 then 100
            when active_days_30d >= 10 then 70
            when active_days_30d >= 5  then 40
            else                            10
        end                                                   as usage_points,

        -- Pontos SLA (0-100)
        greatest(0, 100 - sla_breaches * 15)                  as sla_points

    from joined
),

final as (
    select
        *,

        -- Health Score: 35% churn + 30% NPS + 25% uso + 10% SLA
        least(100, greatest(0, round(
            (1 - churn_probability) * 35
            + nps_normalized        * 0.30
            + usage_points          * 0.25
            + sla_points            * 0.10
        , 1)))                                                as health_score,

        -- Lifecycle derivado (sobrescreve status original se necessário)
        case
            when lifecycle_stage = 'churned'             then 'churned'
            when churn_risk_level = 'HIGH'               then 'at_risk'
            when days_to_renewal is not null
             and days_to_renewal <= 30
             and churn_risk_level != 'LOW'               then 'at_risk'
            else                                              'active'
        end                                                   as derived_lifecycle_stage,

        -- AI recommendations placeholder (gerado pelo SP de recomendações)
        array_construct(churn_recommended_action)             as ai_recommendations,

        current_timestamp()                                   as _dbt_updated_at

    from scored
)

select * from final

{% if is_incremental() %}
    -- Em runs incrementais, reprocessa clientes modificados nas últimas 25h
    where customer_id in (
        select distinct customer_id from {{ ref('stg_customers') }}
        where updated_at >= dateadd('hour', -25, current_timestamp())
        union
        select distinct customer_id from {{ ref('stg_product_events') }}
        where occurred_at >= dateadd('hour', -25, current_timestamp())
        union
        select distinct customer_id from {{ ref('stg_tickets') }}
        where created_at >= dateadd('hour', -25, current_timestamp())
    )
{% endif %}
