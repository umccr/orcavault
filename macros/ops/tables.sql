{% macro create_ops_tables() %}
    {#-

    This macro creates the ops tables for tracking watermark positions.

    `ops.cdc_watermark` serves the function of a watermark table, and has one row per DMS source
    table. `position` is the source commit time up to which every model has processed that table,
    and `pending` is where the current run will go to. The position moves forward once a run has
    processed everything up to `pending`, with the next run resuming from there. Both need to be
    tracked because a model cannot reliably infer its position from its own rows, and the next
    run needs to know where to resume from, since otherwise it has no reference point.

    -#}

    {% set create_schema %}
        create schema if not exists ops
    {% endset %}
    {% do run_query(create_schema) %}

    {% set create_cdc_watermark %}
        create table if not exists ops.cdc_watermark (
            {#- The dbt source which is `<source_name>.<table_name>`, one row per DMS source table
                that has a `cdc` tag in models/cdc/_sources.yml. #}
            source_id             varchar(512) not null,
            {#- The source commit time up to which every model has processed the table. This is
                the `pending` of the last complete run. #}
            position              timestamptz,
            {#- The maximum time which this run will ingest for, i.e,
                `least(max(_dms_cdc_timestamp), getdate() − cdc_pending_margin_minutes)`.
                Everything committed up to here is visible and this run will read up to it. #}
            pending               timestamptz,
            {#- The dbt invocation that recorded `pending`. #}
            pending_invocation_id varchar(64),
            {#- The time of the last write. #}
            updated_at            timestamptz  not null default getdate()
        )
        {#- Small table, so copy on every node and specify sortkey. #}
        diststyle all
        sortkey (source_id)
    {% endset %}
    {% do run_query(create_cdc_watermark) %}
{% endmacro %}
