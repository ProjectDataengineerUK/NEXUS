{{
    config(
        tags=["staging", "transactions"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'transactions') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        transaction_id,
        org_id,
        customer_id,
        null::varchar(36)                                     as subscription_id,

        lower(coalesce(transaction_type, 'unknown'))          as transaction_type,
        lower(coalesce(status, 'completed'))                  as status,

        cast(coalesce(amount, 0) as decimal(18, 2))           as amount,
        upper(coalesce(currency, 'USD'))                      as currency,

        -- normaliza para USD (stub — expandir com fx_rates se necessário)
        cast(coalesce(amount, 0) as decimal(18, 2))           as amount_usd,

        cast(transaction_date as date)                        as transaction_date,
        date_trunc('month', transaction_date)                 as transaction_month,
        current_timestamp()                                   as _dbt_loaded_at

    from source
    where transaction_id is not null
      and status = 'completed'
)

select * from renamed
