{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Override padrão: usa o custom_schema_name diretamente (sem prefixo do target schema).
        Assim `+schema: MART` → NEXUS_APP.MART, não NEXUS_APP.STAGING_MART.
    #}
    {%- if custom_schema_name is none -%}
        {{ target.schema | upper }}
    {%- else -%}
        {{ custom_schema_name | upper }}
    {%- endif -%}
{%- endmacro %}
