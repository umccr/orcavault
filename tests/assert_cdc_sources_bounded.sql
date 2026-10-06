{#-

    This checks that every model that reads an orcabus source calls the bounded macro for that
    source, effectively making use of the watermarking table. It checks all the `cdc_` style macros.
    The macros also error if the source doesn't have a `cdc` tag, so a model can only read an
    orcabus source once it has both the tag and the bound.

    It doesn't check the other direction, that every `cdc` tagged source has a model reading it.
    A tagged source that nothing reads isn't a problem, it just costs an extra query when updating
    `pending`.

-#}

{%- set bound_call = modules.re.compile("cdc_\\w+\\(\\s*'(\\w+)'\\s*,\\s*'(\\w+)'") -%}

{%- if execute -%}
{%- for model in graph.nodes.values() if model.resource_type == 'model' -%}
    {%- set bounded = bound_call.findall(model.raw_code) | map('join', '.') | list -%}
    {%- for source_name, table_name in model.sources -%}
        {%- set source_id = source_name ~ '.' ~ table_name -%}
        {%- if source_name.startswith('orcabus_') and source_id not in bounded %}
            select '{{ model.name }}' as model, '{{ source_id }}' as source_id union all
        {%- endif -%}
    {%- endfor -%}
{%- endfor -%}
{%- endif %}

select cast(null as varchar) as model, cast(null as varchar) as source_id where false
