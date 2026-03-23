{#
  Override del macro por defecto de dbt para nombrar schemas.

  Por defecto, dbt genera nombres de schema como:
    <target_schema>_<custom_schema>  (ej: dbo_bronze)

  Este override hace que se use directamente el custom_schema definido
  en dbt_project.yml (ej: bronze, silver, gold, seeds, snapshots),
  sin anteponer el schema del target.

  Si no hay custom_schema, se usa el schema del target (ej: dbo).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
