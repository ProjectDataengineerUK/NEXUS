{{
    config(
        tags=["intermediate", "subscriptions"],
        post_hook="ALTER TABLE {{ this }} CLUSTER BY (org_id)"
    )
}}

with subs as (
    select * from {{ ref('stg_subscriptions') }}
),

metrics as (
    select
        org_id,
        customer_id,

        -- receita ativa (somente subs active)
        sum(case when status = 'active' then mrr else 0 end)              as mrr,
        sum(case when status = 'active' then arr else 0 end)              as arr,
        sum(case when status = 'active' then seats else 0 end)            as total_seats,
        count(case when status = 'active' then 1 end)                     as active_subscriptions,

        -- renovação mais próxima
        min(case when status = 'active' and renewal_date >= current_date()
                 then renewal_date end)                                   as nearest_renewal_date,

        datediff('day', current_date(),
            min(case when status = 'active' and renewal_date >= current_date()
                     then renewal_date end))                              as days_to_renewal,

        -- plano dominante
        mode(case when status = 'active' then plan_tier end)              as primary_plan_tier,

        -- flags
        max(case when status = 'active' and plan_tier = 'enterprise'
                 then 1 else 0 end)                                       as is_enterprise,
        count_if(status = 'cancelled')                                    as cancelled_subs

    from subs
    group by 1, 2
)

select * from metrics
