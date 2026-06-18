{{
    config(
        tags=["staging", "contracts"]
    )
}}

with source as (
    select * from {{ source('nexus_core', 'contracts') }}
    where org_id = '{{ var("org_id") }}'
),

renamed as (
    select
        contract_id,
        org_id,
        customer_id,
        document_id,

        trim(coalesce(contract_name, 'Unnamed Contract'))      as contract_name,
        lower(coalesce(status, 'active'))                      as contract_status,
        coalesce(auto_renewal, false)                          as auto_renewal,
        coalesce(source_system, 'unknown')                     as source_system,

        cast(coalesce(contract_value, 0) as decimal(18, 2))    as contract_value,
        cast(coalesce(contract_value, 0) as decimal(18, 2))    as contract_arr,

        cast(start_date as date)                               as start_date,
        cast(end_date as date)                                 as end_date,

        datediff('day', current_date(), end_date)              as days_remaining,
        (datediff('day', current_date(), end_date) <= 90
            and lower(coalesce(status, 'active')) = 'active')  as is_expiring_soon,

        extracted_fields,
        risk_flags,

        cast(created_at as timestamp_tz)                       as created_at,
        cast(updated_at as timestamp_tz)                       as updated_at,
        current_timestamp()                                    as _dbt_loaded_at

    from source
    where contract_id is not null
)

select * from renamed
