{{
    config(
        tags=["staging", "tickets"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'tickets') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        ticket_id,
        org_id,
        customer_id,
        null::varchar(36)                                     as subscription_id,

        trim(subject)                                         as subject,
        lower(coalesce(status, 'open'))                       as status,
        lower(coalesce(priority, 'medium'))                   as priority,
        null::varchar(50)                                     as category,
        null::varchar(50)                                     as channel,

        coalesce(sla_breach, false)                           as sla_breached,
        null::integer                                         as first_response_minutes,
        null::integer                                         as resolution_minutes,

        -- normaliza sentiment -1..1
        case
            when sentiment_score > 0.2  then 'positive'
            when sentiment_score < -0.2 then 'negative'
            else                             'neutral'
        end                                                   as sentiment_label,
        cast(sentiment_score as decimal(4, 3))                as sentiment_score,

        cast(created_at as timestamp_tz)                      as created_at,
        cast(resolved_at as timestamp_tz)                     as resolved_at,

        -- duração em horas
        case
            when resolved_at is not null
            then datediff('hour', created_at, resolved_at)
            else null
        end                                                   as resolution_hours,

        current_timestamp()                                   as _dbt_loaded_at

    from source
    where ticket_id is not null
)

select * from renamed
