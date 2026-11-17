{% macro cdc_sources_read(model) %}
    {#-

    This gets the `cdc` tagged sources that a model reads when it is built, as a list of their
    unique ids. It follows the model's ephemeral and view parents recursively, because they
    hold no rows of their own, so what they read is read by the model that selects from them.

    -#}

    {% set read = [] %}
    {% for parent_id in model.depends_on.nodes %}
        {% set cdc_source = graph.sources.get(parent_id) %}
        {% set parent = graph.nodes.get(parent_id) %}

        {#- A model that stores its own rows isn't recursively followed, as it has
            already read the window using it's own `load_bound` instead. -#}
        {% if cdc_source and 'cdc' in cdc_source.tags %}
            {% do read.append(parent_id) %}
        {% elif parent and parent.config.materialized in ['ephemeral', 'view'] %}
            {% do read.extend(cdc_sources_read(parent)) %}
        {% endif %}
    {% endfor %}

    {{ return(read | unique | list) }}
{% endmacro %}

{% macro cdc_sources_selected() %}
    {#-

    This gets the `cdc` tagged sources that this run reads. A run reads a source when it selects
    at least one of its readers, so a run with `--select` only gets the sources that it needs, and
    a full run gets everything.

    -#}

    {#- Ephemeral models and views aren't readers since they don't actually build and store results. -#}
    {% set models = graph.nodes.values()
        | selectattr('resource_type', 'equalto', 'model')
        | rejectattr('config.materialized', 'in', ['ephemeral', 'view'])
        | list %}

    {% set readers = {} %}
    {% for model in models %}
        {% for unique_id in cdc_sources_read(model) %}
            {% do readers.setdefault(unique_id, []).append(model) %}
        {% endfor %}
    {% endfor %}

    {% set selected = [] %}
    {% for unique_id, source_readers in readers | dictsort %}
        {% set selected_readers = source_readers | selectattr('unique_id', 'in', selected_resources) | list %}
        {% if selected_readers %}
            {% do selected.append({'node': graph.sources[unique_id], 'readers': source_readers}) %}
        {% endif %}
    {% endfor %}

    {{ return(selected) }}
{% endmacro %}

{% macro update_source_pending() %}
    {#-

    This macro updates `ops.cdc_watermark.pending` for each DMS source table that this run reads,
    at the beginning of the run. Models will read this value to know up to where they should do
    incremental loads. This value is the table's largest `_dms_cdc_timestamp`, and the next run
    continues from a margin before it after this run is complete. It must be tracked from the
    beginning as otherwise the update won't know where to go from next.

    -#}

    {% if not execute or flags.WHICH not in ['run', 'build'] %}
        {{ return('') }}
    {% endif %}

    {#- A personal target should not touch the watermarks, see README_DEV.md. -#}
    {% if is_personal_target() %}
        {{ return('') }}
    {% endif %}

    {#- The tables which have a `cdc` tag in models/cdc/_sources.yml. -#}
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

    {#- Only the tables that this run reads get a `pending`. The others keep the `pending` and the
        `pending_invocation_id` of the last run that read them, meaning this run can't update their positions. -#}
    {% set selected = cdc_sources_selected() %}
    {% if not selected %}
        {% do log('CDC pending not updated: no selected model reads a CDC source', info=true) %}
        {{ return('') }}
    {% endif %}

    {#- Then it is updated with the pending position, which is the newest visible commit. There is no margin
        here, so a table that stops receiving commits still has its last commits read. -#}
    {% set update_pending %}
        update ops.cdc_watermark
        set pending               = newest_by_source.newest,
            pending_invocation_id = '{{ invocation_id }}',
            updated_at            = getdate()
        from (
            {%- for cdc_source in selected %}
                {%- set node = cdc_source.node %}
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

    {% do log(
        'CDC pending updated: ' ~ response.rows_affected ~ ' of ' ~ sources | length
            ~ ', earliest: ' ~ pending_range[0] ~ ', latest: ' ~ pending_range[1],
        info=true
    ) %}
{% endmacro %}

{% macro update_source_positions(results) %}
    {#-

    This macro updates the `ops.cdc_watermark.position` to a margin before the new `pending` value
    after the run, for each DMS source table whose readers all succeeded. This is the reference
    point for the next run, and is used to continue incremental loads from. The margin means the
    next run reads the last commits again, which finds rows committed before `pending` that weren't
    visible yet.

    Each table is decided on its own, so a failed model only prevents updating the tables that it reads,
    and a run with `--select` updates the tables whose readers use it.

    -#}

    {% if not execute or flags.WHICH not in ['run', 'build'] %}
        {{ return('') }}
    {% endif %}

    {#- A personal target reads the daily run's watermark and leaves it alone, see README_DEV.md. -#}
    {% if is_personal_target() %}
        {{ return('') }}
    {% endif %}

    {#- Also need to omit legacy and empty runs otherwise the position would incorrectly go forward. #}
    {% if var('load_legacy', false) or invocation_args_dict.get('empty') %}
        {{ return('') }}
    {% endif %}

    {% set succeeded = results
        | selectattr('status', 'equalto', 'success')
        | map(attribute='node.unique_id')
        | list %}

    {#- The run read no CDC source. -#}
    {% set selected = cdc_sources_selected() %}
    {% if not selected %}
        {{ return('') }}
    {% endif %}

    {#- A table's position can move once every model that reads it has succeeded in this run, as
        a reader that failed, was skipped or wasn't selected would miss the window if the position
        moved without it. The models downstream don't use this mechanism, and instead use `load_bound`. -#}
    {% set complete = [] %}
    {% for cdc_source in selected %}
        {% set source_id = cdc_source.node.source_name ~ '.' ~ cdc_source.node.name %}
        {# Gets all models that were read and removes all succeeded readers, leaving only the failures. #}
        {% set not_succeeded = cdc_source.readers
            | rejectattr('unique_id', 'in', succeeded)
            | map(attribute='name')
            | sort %}

        {% if not_succeeded %}
            {% do log('CDC position not updated: ' ~ source_id ~ ', waiting on ' ~ not_succeeded | join(', '), info=true) %}
        {% else %}
            {% do complete.append(source_id) %}
        {% endif %}
    {% endfor %}

    {% if not complete %}
        {% do log('CDC positions updated to pending: 0 of ' ~ selected | length, info=true) %}
        {{ return('') }}
    {% endif %}

    {#- A table with no visible commits has a null `pending`, which should not clear its position. #}
    {% set promote %}
        update ops.cdc_watermark
        set position   = coalesce(
                             dateadd(minute, -{{ var('cdc_position_margin_minutes', 10) | int }}, cast(pending as timestamp)),
                             position
                         ),
            updated_at = getdate()
        where pending_invocation_id = '{{ invocation_id }}'
          and source_id in ('{{ complete | join("', '") }}')
    {% endset %}
    {% set response = adapter.execute(promote, auto_begin=false)[0] %}

    {% do log('CDC positions updated to pending: ' ~ response.rows_affected ~ ' of ' ~ selected | length, info=true) %}
{% endmacro %}
