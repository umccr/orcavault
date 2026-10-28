{% materialization clone, adapter='redshift' %}

    {#-

    This replaces dbt's clone, which `dbt_clone` in dx.sh uses to put a view of the dev daily run's table in a personal
    schema for each model the developer hasn't changed, see README_DEV.md. Redshift can't clone a table, so dbt's clone
    also makes a view, but a normal view is tied to the table it reads. The daily run rebuilds a table by renaming it
    and dropping it with `cascade`, which would drop the view as well, so this makes a late-binding view instead.

    -#}

    {%- if not defer_relation -%}
        {{ log('No relation found in state manifest for ' ~ model.unique_id, info=true) }}
        {{ return({'relations': []}) }}
    {%- endif -%}

    {%- set existing_relation = load_cached_relation(this) -%}
    {%- if existing_relation and not flags.FULL_REFRESH -%}
        {{ log('Relation ' ~ existing_relation ~ ' already exists', info=true) }}
        {{ return({'relations': []}) }}
    {%- endif -%}

    {%- set target_relation = this.incorporate(type='view') -%}
    {{ drop_relation_if_exists(existing_relation) }}

    {% call statement('main') -%}
        create view {{ target_relation }} as select * from {{ defer_relation }} with no schema binding
    {%- endcall %}
    {{ adapter.commit() }}

    {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
