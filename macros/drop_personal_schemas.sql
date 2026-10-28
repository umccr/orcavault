{% macro drop_personal_schemas(dry_run=false) %}

    {#-

    This drops a personal target's schemas, which `dbt_drop` in dx.sh runs, see README_DEV.md. It refuses to run for
    the daily run's target. It only drops the schemas this project builds for the target, and only those prefixed with
    the target schema, e.g. `dev_marko_dcl`. So it can't drop a shared schema, or another developer's unless the target
    schema is theirs.

    -#}

    {% if not is_personal_target() %}
        {{ exceptions.raise_compiler_error('The target schema is ' ~ target.schema ~ ', which would drop the shared schemas') }}
    {% endif %}

    {% set schemas = [] %}
    {% for node in graph.nodes.values() if node.schema not in schemas %}
        {% do schemas.append(node.schema) %}
    {% endfor %}

    {% for schema in schemas | sort if schema.startswith(target.schema ~ '_') %}
        {% if dry_run %}
            {% do log('Would drop ' ~ schema ~ ' if it exists', info=true) %}
        {% elif adapter.check_schema_exists(target.database, schema) %}
            {% do adapter.drop_schema(api.Relation.create(database=target.database, schema=schema)) %}
            {% do log('Dropped ' ~ schema, info=true) %}
        {% endif %}
    {% endfor %}

{% endmacro %}
