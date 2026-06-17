{{
    config(
        tags=["staging", "customers"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'customers') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        customer_id,
        org_id,

        -- identidade
        trim(name)                                               as customer_name,
        lower(trim(email))                                       as email,
        trim(phone)                                              as phone,

        -- segmentação
        upper(coalesce(segment, 'UNKNOWN'))                      as segment,
        upper(coalesce(region, 'UNKNOWN'))                       as region,
        lower(coalesce(industry, 'unknown'))                     as industry,

        -- status
        lower(coalesce(status, 'active'))                        as status,
        lower(coalesce(lifecycle_stage, 'active'))               as lifecycle_stage,

        -- métricas
        cast(nps_score as integer)                               as nps_score,

        -- datas
        cast(customer_since as timestamp_tz)                     as customer_since,
        cast(updated_at as timestamp_tz)                         as updated_at,

        -- auditoria dbt
        current_timestamp()                                      as _dbt_loaded_at

    from source
    where customer_id is not null
      and name is not null
)

select * from renamed
