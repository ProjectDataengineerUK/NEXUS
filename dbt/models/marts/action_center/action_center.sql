{{
    config(
        materialized='table',
        tags=["mart", "action_center", "gold"],
        post_hook=[
            "ALTER TABLE {{ this }} CLUSTER BY (org_id, priority)",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_VIEWER"
        ]
    )
}}

with recs as (
    select * from {{ source('nexus_ai', 'recommendations') }}
    where org_id = '{{ var("org_id") }}'
      and is_active = true
      and status not in ('completed', 'dismissed')
),

c360 as (
    select
        customer_id,
        customer_name,
        segment,
        health_score,
        churn_risk_level,
        churn_probability,
        arr,
        nearest_renewal_date,
        nps_score,
        open_tickets
    from {{ ref('customer_360') }}
),

joined as (
    select
        r.recommendation_id,
        r.org_id,
        r.entity_id                                              as customer_id,
        c.customer_name,
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

        -- contexto do cliente
        c.health_score,
        c.churn_risk_level,
        c.churn_probability,
        c.arr,
        c.nearest_renewal_date,
        c.nps_score,
        c.open_tickets,

        -- score de priorização: priority weight × impacto financeiro normalizado
        case r.priority
            when 'HIGH'   then 3
            when 'MEDIUM' then 2
            else               1
        end * (1 + coalesce(r.expected_impact_usd, 0) / 100000.0) as priority_score,

        current_timestamp()                                      as _dbt_updated_at

    from recs r
    left join c360 c on r.entity_id = c.customer_id
)

select * from joined
order by priority_score desc
