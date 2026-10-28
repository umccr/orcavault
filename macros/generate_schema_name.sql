{% macro generate_schema_name(custom_schema_name, node) -%}

    {#-

    The daily run builds into the shared schemas, e.g. `dcl`. A personal target builds into its own
    copy of each one, prefixed with the target schema, e.g. `dev_marko_dcl`, see README_DEV.md.

    -#}

    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- elif is_personal_target() -%}

        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- else -%}

        {{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}


{% macro is_personal_target() -%}

    {#- The daily run uses the `public` target schema, and any other is a developer's personal schema. -#}
    {{ return(target.schema != 'public') }}

{%- endmacro %}
