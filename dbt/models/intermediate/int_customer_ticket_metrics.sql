{{
    config(
        tags=["intermediate", "tickets"],
        post_hook="ALTER TABLE {{ this }} CLUSTER BY (org_id)"
    )
}}

with tickets as (
    select * from {{ ref('stg_tickets') }}
),

metrics as (
    select
        org_id,
        customer_id,

        count(*)                                                          as total_tickets,
        count_if(status = 'open')                                         as open_tickets,
        count_if(status = 'resolved')                                     as resolved_tickets,
        count_if(priority in ('high', 'critical'))                        as high_priority_tickets,
        count_if(sla_breached = true)                                     as sla_breaches,

        round(avg(case when sentiment_score is not null
                  then sentiment_score end), 3)                           as avg_sentiment_score,
        mode(sentiment_label)                                             as dominant_sentiment,

        round(avg(case when resolution_hours is not null
                  then resolution_hours end), 1)                          as avg_resolution_hours,
        round(avg(first_response_minutes), 0)                             as avg_first_response_min,

        max(created_at)                                                   as last_ticket_at,

        -- tickets dos últimos 30 dias
        count_if(created_at >= dateadd('day', -30, current_timestamp()))  as tickets_30d,
        count_if(created_at >= dateadd('day', -30, current_timestamp())
                 and sla_breached = true)                                 as sla_breaches_30d

    from tickets
    group by 1, 2
)

select * from metrics
