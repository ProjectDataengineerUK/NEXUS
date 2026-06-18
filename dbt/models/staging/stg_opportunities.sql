{{
    config(
        tags=["staging", "opportunities"],
        materialized="view"
    )
}}

with source as (
    select * from {{ source('nexus_core', 'opportunities') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        opportunity_id,
        org_id,
        customer_id,
        subscription_id,

        trim(opportunity_name)                                as opportunity_name,
        lower(coalesce(opportunity_type, 'expansion'))        as opportunity_type,  -- new_business|expansion|renewal|upsell|cross_sell
        lower(coalesce(stage, 'prospecting'))                 as stage,             -- prospecting|qualification|proposal|negotiation|closed_won|closed_lost

        coalesce(amount_usd, 0)                               as amount_usd,
        coalesce(probability_pct, 50)                         as probability_pct,
        coalesce(amount_usd, 0) * coalesce(probability_pct, 50) / 100
                                                              as weighted_amount_usd,

        cast(close_date as date)                              as close_date,
        datediff('day', current_date(), cast(close_date as date))
                                                              as days_to_close,

        trim(owner_name)                                      as owner_name,
        trim(owner_email)                                     as owner_email,

        -- Flags
        (lower(stage) = 'closed_won')                         as is_won,
        (lower(stage) = 'closed_lost')                        as is_lost,
        (lower(stage) not in ('closed_won','closed_lost'))    as is_open,
        (close_date < current_date() and lower(stage) not in ('closed_won','closed_lost'))
                                                              as is_overdue,

        -- Quadrant de prioridade
        case
            when probability_pct >= 70 and amount_usd >= 50000 then 'A_PRIORITY'
            when probability_pct >= 50 and amount_usd >= 20000 then 'B_PRIORITY'
            when probability_pct >= 30                          then 'C_PIPELINE'
            else 'D_NURTURE'
        end                                                   as priority_quadrant,

        coalesce(source_channel, 'unknown')                   as source_channel,
        coalesce(competitor, 'none')                          as primary_competitor,

        cast(created_at as timestamp_tz)                      as created_at,
        cast(updated_at as timestamp_tz)                      as updated_at,
        current_timestamp()                                   as _dbt_loaded_at

    from source
    where opportunity_id is not null
      and customer_id is not null
)

select * from renamed
