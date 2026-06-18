{{
    config(
        alias='revenue_daily',
        materialized='incremental',
        unique_key=['revenue_date', 'org_id'],
        incremental_strategy='merge',
        tags=["mart", "revenue", "gold"],
        post_hook=[
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_VIEWER"
        ]
    )
}}

-- Mart de receita diária: ARR, MRR, e movimentos de receita (new/expansion/churn/contraction).
-- Incremental — reprocessa 30 dias para capturar late-arriving transactions.

with transactions as (
    select * from {{ ref('stg_transactions') }}
    {% if is_incremental() %}
        where transaction_date >= dateadd('day', -30, current_date())
    {% endif %}
),

daily_revenue as (
    select
        org_id,
        transaction_date                                                     as revenue_date,

        sum(case when transaction_type = 'new_contract'
                 then amount_usd / 12.0 else 0 end)                          as new_mrr,

        sum(case when transaction_type = 'upsell'
                 then amount_usd / 12.0 else 0 end)                          as expansion_mrr,

        sum(case when transaction_type = 'downgrade'
                 then amount_usd / 12.0 else 0 end)                          as contraction_mrr,

        sum(case when transaction_type = 'churn'
                 then amount_usd / 12.0 else 0 end)                          as churn_mrr,

        sum(case when transaction_type = 'renewal'
                 then amount_usd / 12.0 else 0 end)                          as renewal_mrr,

        sum(amount_usd)                                                       as total_revenue_booked,
        count(distinct transaction_id)                                        as transaction_count,
        count(distinct customer_id)                                           as customers_transacted

    from transactions
    group by 1, 2
),

with_net as (
    select
        *,
        new_mrr + expansion_mrr - contraction_mrr - churn_mrr               as net_new_mrr,
        (new_mrr + expansion_mrr - contraction_mrr - churn_mrr) * 12        as net_new_arr,
        current_timestamp()                                                   as _dbt_updated_at
    from daily_revenue
)

select * from with_net
