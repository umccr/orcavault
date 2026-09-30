{% macro update_model_position() %}
    {#-

    This macro updates the model position in the `meta.model_position` table
    for follow up runs to have a comparison inside `watermark_bound`. Using an
    upsert with `merge into`, itt runs as a post-hook during the dbt run flow
    and commits in the same transaction as the model's rows, meaning that it
    cannot incorrect progress the position.

    -#}

    {% if model.config.get('materialized') != 'incremental' %}
        {{ return('') }}
    {% endif %}

    {#- Only models that actually read a position need to write one. -#}
    {% if 'watermark_bound' not in (model.raw_code or '') %}
        {{ return('') }}
    {% endif %}

    {#- We must consider legacy loading as separate, and it should not be tracked by the
        watermark bound. -#}
    {% if var('load_legacy', false) %}
        {{ return('') }}
    {% endif %}

    {% set sql %}
        merge into meta.model_position
            using (
                select
                    '{{ model.unique_id }}'                     as model_id,
                    cast('{{ run_started_at }}' as timestamptz) as position,
                    max(load_datetime)                          as target_max_at_write,
                    '{{ invocation_id }}'                       as invocation_id
                from {{ this }}
            ) as src
            on meta.model_position.model_id = src.model_id
        when matched then update set
            position            = src.position,
            target_max_at_write = src.target_max_at_write,
            invocation_id       = src.invocation_id,
            updated_at          = getdate()
        when not matched then insert
            (model_id, position, target_max_at_write, invocation_id, updated_at)
            values (src.model_id, src.position, src.target_max_at_write, src.invocation_id, getdate())
    {% endset %}

    {{ return(sql) }}
{% endmacro %}

{% macro update_model_run(results) %}
    {#-

    This macro  updates the model run in the `meta.model_run` with the metadata
    for that run. This is an append-only log, and is used for informational
    purposes only. It should not be read by any models in the warehouse.

    -#}

    {#- Nothing was run, so return early as there is nothing to insert. -#}
    {% if not results %}
        {{ return('') }}
    {% endif %}

    {% set insert %}
        insert into meta.model_run (
            invocation_id,
            run_started_at,
            target_name,
            node_id,
            node_name,
            resource_type,
            materialization,
            status,
            rows_affected,
            execution_time,
            message
        )
        values
        {%- for result in results %}
            {%- set rows_affected = result.adapter_response.rows_affected %}
            {#- Cut to 2048 bytes of UTF-8 as Redshift varchar lengths are bytes. -#}
            {%- set message = (result.message or '').encode('utf-8')[:2048].decode('utf-8', 'ignore') | replace("'", "''") %}
            (
                '{{ invocation_id }}',
                cast('{{ run_started_at }}' as timestamptz),
                '{{ target.name }}',
                '{{ result.node.unique_id }}',
                '{{ result.node.name }}',
                '{{ result.node.resource_type }}',
                nullif('{{ result.node.config.get("materialized") or "" }}', ''),
                '{{ result.status }}',
                {{ rows_affected if rows_affected is number else 'null' }},
                {{ result.execution_time }},
                nullif('{{ message }}', '')
            ){{ ',' if not loop.last }}
        {%- endfor %}
    {% endset %}
    {% do run_query(insert) %}
{% endmacro %}
