{% macro update_source_pending() %}
    {#-

    This macro updates `ops.cdc_watermark.pending` for each DMS source table for the beginning
    of the run. Models will read this value to know from where they should do incremental loads.
    This value is table's largest `_dms_cdc_timestamp`, and represents the next point that the
    model will go from after this run is complete, minus a margin to prevent missing commits.
    It must be tracked from the beginning as otherwise the update won't know where to go from
    next.

    -#}

    {% if not execute or flags.WHICH not in ['run', 'build'] %}
        {{ return('') }}
    {% endif %}

    {#- The tables which as a `cdc` tag in models/cdc/_sources.yml. -#}
    {% set sources = [] %}
    {% for node in graph.sources.values() | sort(attribute='unique_id') if 'cdc' in node.tags %}
        {% do sources.append(node) %}
    {% endfor %}
    {% if not sources %}
        {{ return('') }}
    {% endif %}

    {#- A table with a `cdc` tag gets an initial row with no position. -#}
    {% set insert_new %}
        insert into ops.cdc_watermark (source_id)
        select source_id from (
            {%- for node in sources %}
                select '{{ node.source_name }}.{{ node.name }}' as source_id
                {%- if not loop.last %}
                    union all
                {%- endif %}
            {%- endfor %}
        ) cdc_sources
        where source_id not in (select source_id from ops.cdc_watermark)
    {% endset %}
    {% set inserted = adapter.execute(insert_new, auto_begin=false)[0] %}
    {% do log('CDC positions inserted: ' ~ inserted.rows_affected, info=true) %}

    {#- Then it is updated with the pending position. -#}
    {% set update_pending %}
        update ops.cdc_watermark
        set pending               = dateadd(minute, -{{ var('cdc_pending_margin_minutes', 10) | int }}, newest_by_source.newest),
            pending_invocation_id = '{{ invocation_id }}',
            updated_at            = getdate()
        from (
            {%- for node in sources %}
                {%- set source_id = node.source_name ~ '.' ~ node.name %}
                {%- set partition_expression = node.meta.get('cdc_partition_expression') %}
                {%- set position = cdc_watermark_value(node.source_name, node.name, 'position') %}
                select '{{ source_id }}' as source_id, cast(max(_dms_cdc_timestamp) as timestamp) as newest
                from {{ node.relation_name }}
                {%- if partition_expression %}
                    where {{ partition_expression }} >= coalesce(
                        to_char(dateadd(day, -1, cast({{ position }} as timestamp)), 'YYYYMMDD'),
                        '00000000'
                    )
                {%- endif %}

                {%- if not loop.last %}
                    union all
                {%- endif %}
            {%- endfor %}
        ) newest_by_source
        where ops.cdc_watermark.source_id = newest_by_source.source_id
    {% endset %}
    {% set response = adapter.execute(update_pending, auto_begin=false)[0] %}

    {% set select_range %}
        select min(pending), max(pending) from ops.cdc_watermark where pending_invocation_id = '{{ invocation_id }}'
    {% endset %}
    {% set pending_range = adapter.execute(select_range, auto_begin=false, fetch=true)[1].rows[0] %}

    {% do log('CDC pending updated: ' ~ response.rows_affected ~ ', earliest: ' ~ pending_range[0] ~ ', latest: ' ~ pending_range[1], info=true) %}
{% endmacro %}

{% macro update_source_positions(results) %}
    {#-

    This macro updates the `ops.cdc_watermark.position` to the new `pending value after the run
    as successfully completed. This is the reference point for the next run, and is used to continue
    incremental loads from.

    -#}

    {% if not execute or flags.WHICH not in ['run', 'build'] %}
        {{ return('') }}
    {% endif %}
    {#- Also need to omit legacy and empty runs otherwise the position would incorrectly go forward. #}
    {% if var('load_legacy', false) or invocation_args_dict.get('empty') %}
        {{ return('') }}
    {% endif %}

    {#- Count the number of successes to determine whether to continue. Ephemeral models are
        excluded because results doesn't include them, which would always fail the condition. -#}
    {% set models = graph.nodes.values()
        | selectattr('resource_type', 'equalto', 'model')
        | rejectattr('config.materialized', 'equalto', 'ephemeral')
        | list %}
    {% set succeeded = results
        | selectattr('node.resource_type', 'equalto', 'model')
        | selectattr('status', 'equalto', 'success')
        | list %}
    {% if succeeded | length != models | length %}
        {% do log('CDC positions not updated: ' ~ succeeded | length ~ ' of ' ~ models | length ~ ' models succeeded', info=true) %}
        {{ return('') }}
    {% endif %}

    {% set promote %}
        update ops.cdc_watermark
        set position   = pending,
            updated_at = getdate()
        where pending_invocation_id = '{{ invocation_id }}'
    {% endset %}
    {% set response = adapter.execute(promote, auto_begin=false)[0] %}

    {% do log('CDC positions updated to pending: ' ~ response.rows_affected, info=true) %}
{% endmacro %}
