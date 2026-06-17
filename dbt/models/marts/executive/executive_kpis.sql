{{
    config(
        alias='executive_kpis',
        materialized='incremental',
        unique_key=['snapshot_date', 'org_id'],
        incremental_strategy='merge',
        tags=["mart", "executive", "gold", "kpis"],
        post_hook=[
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_VIEWER"
        ]
    )
}}

-- Snapshot diário de KPIs executivos consumido por Home.py e executive_kpis.yaml.
-- Uma linha por (org_id, snapshot_date). Incremental — append diário.

with customers as (
    select * from {{ ref('customer_360') }}

    {% if is_incremental() %}
        -- apenas reprocessa orgs com dados atualizados hoje
        where _dbt_updated_at >= dateadd('hour', -25, current_timestamp())
    {% endif %}
),

churn_scores as (
    select customer_id, org_id, risk_level, expected_revenue_at_risk
    from {{ source('nexus_ai', 'churn_scores') }}
    qualify row_number() over (partition by customer_id order by scored_at desc) = 1
),

recommendations as (
    select org_id, count(*) as cnt, sum(expected_impact_usd) as total_impact
    from {{ source('nexus_ai', 'recommendations') }}
    where status = 'pending' and is_active = true
    group by 1
),

tickets as (
    select
        org_id,
        count_if(status = 'open')                              as open_tickets,
        count_if(status = 'open' and priority = 'urgent')     as urgent_tickets
    from {{ source('nexus_core', 'tickets') }}
    group by 1
),

kpis as (
    select
        c.org_id,
        current_date()                                        as snapshot_date,

        -- Receita
        sum(case when c.lifecycle_stage != 'churned' then c.arr else 0 end)  as total_arr,
        sum(case when c.lifecycle_stage != 'churned' then c.mrr else 0 end)  as total_mrr,

        -- Contagem de clientes
        count_if(c.lifecycle_stage = 'active')                as active_customers,
        count_if(c.lifecycle_stage = 'at_risk')               as at_risk_customers,
        count_if(c.lifecycle_stage = 'churned')               as churned_customers,
        count(*)                                               as total_customers,

        -- Saúde
        round(avg(case when c.lifecycle_stage != 'churned' then c.health_score end), 1)  as avg_health_score,
        round(avg(case when c.lifecycle_stage != 'churned' then c.nps_score end), 1)     as avg_nps,

        -- ARR em risco (HIGH + MEDIUM churn)
        sum(case when cs.risk_level in ('HIGH','MEDIUM')
                 then coalesce(cs.expected_revenue_at_risk, 0) else 0 end)   as arr_at_risk,

        -- Renovações próximas (90 dias)
        sum(case
            when c.lifecycle_stage in ('active','at_risk')
             and c.nearest_renewal_date <= dateadd('day', 90, current_date())
            then c.arr else 0
        end)                                                  as renewals_90d_arr,

        -- Suporte
        coalesce(max(t.open_tickets), 0)                      as open_tickets,
        coalesce(max(t.urgent_tickets), 0)                    as urgent_tickets,

        -- Recomendações de IA
        coalesce(max(r.cnt), 0)                               as pending_recommendations,
        coalesce(max(r.total_impact), 0)                      as total_expected_impact

    from customers c
    left join churn_scores   cs on c.customer_id = cs.customer_id and c.org_id = cs.org_id
    left join tickets         t on c.org_id = t.org_id
    left join recommendations r on c.org_id = r.org_id
    group by c.org_id
)

select * from kpis
