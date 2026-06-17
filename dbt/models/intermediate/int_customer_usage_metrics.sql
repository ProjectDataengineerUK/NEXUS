{{
    config(
        tags=["intermediate", "usage"],
        post_hook="ALTER TABLE {{ this }} CLUSTER BY (org_id)"
    )
}}

with events as (
    select * from {{ ref('stg_product_events') }}
),

metrics as (
    select
        org_id,
        customer_id,

        -- volume total
        count(*)                                                              as total_events,
        count(distinct event_type)                                            as unique_event_types,
        count(distinct feature_name)                                          as features_used,

        -- janelas de uso
        count_if(occurred_date >= dateadd('day', -7,  current_date()))        as events_7d,
        count_if(occurred_date >= dateadd('day', -30, current_date()))        as events_30d,
        count_if(occurred_date >= dateadd('day', -90, current_date()))        as events_90d,

        -- dias ativos
        count(distinct case when occurred_date >= dateadd('day', -30, current_date())
                            then occurred_date end)                           as active_days_30d,
        count(distinct case when occurred_date >= dateadd('day', -7, current_date())
                            then occurred_date end)                           as active_days_7d,

        -- IA
        count_if(is_ai_event = true)                                          as ai_invocations,
        count_if(is_ai_event = true
                 and occurred_date >= dateadd('day', -30, current_date()))    as ai_invocations_30d,

        -- erros
        count_if(is_error_event = true)                                       as error_events,

        -- última atividade
        max(occurred_at)                                                      as last_activity_at,
        datediff('day', max(occurred_at), current_timestamp())                as days_since_last_activity,

        -- tendência: compara 7d vs média semanal de 30d
        case
            when count_if(occurred_date >= dateadd('day', -7,  current_date())) >
                 count_if(occurred_date >= dateadd('day', -30, current_date())) / 4.0 * 1.2
            then 'up'
            when count_if(occurred_date >= dateadd('day', -7,  current_date())) <
                 count_if(occurred_date >= dateadd('day', -30, current_date())) / 4.0 * 0.8
            then 'down'
            else 'stable'
        end                                                                   as usage_trend

    from events
    group by 1, 2
)

select * from metrics
