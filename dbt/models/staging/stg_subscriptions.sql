{{
    config(
        tags=["staging", "subscriptions"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'subscriptions') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        subscription_id,
        org_id,
        customer_id,
        product_id,

        trim(plan_name)                                       as plan_name,
        lower(coalesce(plan_tier, 'standard'))                as plan_tier,
        lower(coalesce(status, 'active'))                     as status,

        coalesce(seats, 1)                                    as seats,
        cast(coalesce(mrr, 0) as decimal(18, 2))              as mrr,
        cast(coalesce(arr, mrr * 12, 0) as decimal(18, 2))   as arr,

        cast(coalesce(current_period_start, created_at) as timestamp_tz) as started_at,
        cast(coalesce(current_period_end, trial_end_date, cancel_at) as date) as renewal_date,
        cast(canceled_at as timestamp_tz)                     as ended_at,

        current_timestamp()                                   as _dbt_loaded_at

    from source
    where subscription_id is not null
      and customer_id is not null
      and status != 'deleted'
)

select * from renamed
