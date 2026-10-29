{% macro generate_schema_name(custom_schema_name, node) -%}

    {#-

    Generate the schema name to use. The daily runs build into shared schemas, and personal targets
    build into a copy of these with a prefix.

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

    {#-

    Determine whether this is a target with a personal schema.

    -#}

    {{ return(target.schema != 'public') }}

{%- endmacro %}
