{{
    config(
        tags=["staging", "product_events"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'product_events') }}
    where org_id = '{{ var("org_id") }}'
      and occurred_at >= dateadd('day', -90, current_timestamp())  -- janela 90d
),

renamed as (
    select
        event_id,
        org_id,
        customer_id,
        subscription_id,

        lower(trim(event_type))                               as event_type,
        lower(trim(coalesce(feature_name, 'unknown')))        as feature_name,
        coalesce(event_value, 1)                              as event_value,
        lower(coalesce(platform, 'web'))                      as platform,
        lower(coalesce(user_role, 'unknown'))                 as user_role,

        cast(occurred_at as timestamp_tz)                     as occurred_at,
        cast(occurred_at as date)                             as occurred_date,

        -- flags de uso
        case when event_type = 'ai_agent_invocation' then true else false end as is_ai_event,
        case when event_type like '%error%'           then true else false end as is_error_event,
        case when event_type = 'login'                then true else false end as is_login,

        current_timestamp()                                   as _dbt_loaded_at

    from source
    where event_id is not null
      and customer_id is not null
)

select * from renamed
