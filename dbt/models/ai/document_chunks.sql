{{
    config(
        alias='document_chunks',
        materialized='incremental',
        unique_key='chunk_id',
        incremental_strategy='merge',
        schema='AI',
        tags=["ai", "silver", "rag"],
        post_hook=[
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ANALYST",
            "GRANT SELECT ON TABLE {{ this }} TO ROLE NEXUS_ADMIN"
        ]
    )
}}

-- Chunking de documentos para Cortex Search (split por parágrafo duplo).
-- Cada linha = um chunk indexável. chunk_id é deterministico via MD5.

with docs as (
    select
        document_id,
        org_id,
        document_name,
        document_type,
        extracted_text
    from {{ source('nexus_core', 'documents') }}
    where extracted_text is not null
      and length(trim(extracted_text)) > 0
    {% if is_incremental() %}
        and created_at >= dateadd('day', -7, current_timestamp())
    {% endif %}
),

-- Split por parágrafos (dupla quebra de linha) usando SPLIT_TO_TABLE
paragraphs as (
    select
        d.document_id,
        d.org_id,
        d.document_name,
        d.document_type,
        f.index                                         as chunk_index,
        trim(f.value::varchar)                          as chunk_text
    from docs d,
         lateral flatten(input => split(d.extracted_text, '\n\n')) f
    where length(trim(f.value::varchar)) > 50
),

final as (
    select
        md5(document_id || '::' || chunk_index::varchar) as chunk_id,
        document_id,
        org_id,
        document_name,
        document_type,
        null::varchar(500)                              as section_title,
        chunk_index,
        chunk_text,
        null::integer                                   as page_number,
        length(chunk_text)                              as char_count,
        current_timestamp()                             as created_at
    from paragraphs
)

select * from final
