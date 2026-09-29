{% macro create_meta_tables() %}
    {#-

    This macro idempotently creates the meta tables for tracking watermark positions and run-time dbt
    information.

    It creates two tables, `meta.model_position` which serves the function of a watermark table that
    tracks the up to date load time for a specific run. This is how all models inside the warehouse are
    able to update incrementally, by comparing again the `position` in the `model_position` table. It
    is written to a table to ensure a centralised location for this logic so that it's not possible
    for the warehouse to ever have a window of time where records could be missed. The `position` only
    moves forward up to the point where the warehouse has processed the current batch of records, and
    then resumes from there on the next run.

    The other table is the `meta.model_run`, which stores information about a run, such as execution time,
    status, config, and other fields. It is an append-only table that is updated at the end of a dbt run,
    and is less critical for correct functioning. Nothing inside the modelling logic should ever read this
    table, it is only for information purposes after the fact.

    -#}

    {% set schema_ddl %}
        create schema if not exists meta
    {% endset %}
    {% do run_query(schema_ddl) %}

    {% set position_ddl %}
        create table if not exists meta.model_position (
            {#- dbt id for the model, one row per model in this warehouse. -#}
            model_id            varchar(512) not null,
            {#- The watermark position, `run_started_at` of the model's last successful run.
                The next run reads rows where the `load_datetime` is later than this. -#}
            position            timestamptz  not null,
            {#- The model's max(load_datetime) at the time when `position` was written. If
                its max is lower than this, rows were deleted and `position` is not valid. -#}
            target_max_at_write timestamptz,
            {#- The dbt invocation that wrote this row. -#}
            invocation_id       varchar(64),
            {#- The time of the last write. -#}
            updated_at          timestamptz  not null default getdate()
        )
        {# Small table, so copy on every node and specify sortkey #}
        diststyle all
        sortkey (model_id)
    {% endset %}
    {% do run_query(position_ddl) %}

    {% set run_ddl %}
        create table if not exists meta.model_run (
            {#- The dbt invocation that the result belongs to. -#}
            invocation_id   varchar(64)  not null,
            {#- The start of the invocation. -#}
            run_started_at  timestamptz  not null,
            {#- The dbt target, e.g. dev or prod. -#}
            target_name     varchar(64)  not null,
            {#- The dbt unique_id of the node. -#}
            node_id         varchar(512) not null,
            {#- The name of the node. -#}
            node_name       varchar(255) not null,
            {#- The resource type, e.g. model, test, seed or snapshot. -#}
            resource_type   varchar(32)  not null,
            {#- The materialization config, e.g. incremental, view or test. -#}
            materialization varchar(32),
            {#- The dbt result status. -#}
            status          varchar(32)  not null,
            {#- The rows that were affected in the run, null if no rows affected. -#}
            rows_affected   bigint,
            {#- The execution time for the node in seconds. -#}
            execution_time  double precision,
            {#- The result message, trunacted to 2048 characters. -#}
            message         varchar(2048),
            {#- The time when this row was inserted. -#}
            recorded_at     timestamptz  not null default getdate()
        )
        {# Append only table that grows, so spread rows and group by a dbt run, i.e. invocation_id #}
        diststyle key
        distkey (invocation_id)
        sortkey (run_started_at, node_id)
    {% endset %}
    {% do run_query(run_ddl) %}
{% endmacro %}
