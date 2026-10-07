{% macro cdc_watermark_value(source_name, table_name, column) -%}
    {#-

    Get an `ops.cdc_watermark.<column>` value from the watermark table. This will check that the
    source has a `cdc` tag and error if it doesn't.

    Unit tests can't mock `ops.cdc_watermark`, so they set the values with the `cdc_watermark_overrides` var instead.

    -#}
    {%- set overrides = var('cdc_watermark_overrides', none) -%}
    {%- if overrides is not none -%}
        {%- set value = overrides.get(source_name ~ '.' ~ table_name, {}).get(column) -%}
        cast({{ "'" ~ value ~ "'" if value else 'null' }} as timestamptz)
    {%- else -%}
        {%- if execute -%}
            {%- set node = graph.sources.get('source.' ~ project_name ~ '.' ~ source_name ~ '.' ~ table_name) -%}
            {%- if node is none or 'cdc' not in node.tags -%}
                {{ exceptions.raise_compiler_error(
                    source_name ~ '.' ~ table_name ~ " has no CDC position: tag it 'cdc' in models/cdc/_sources.yml"
                ) }}
            {%- endif -%}
        {%- endif -%}

        (select p.{{ column }} from ops.cdc_watermark p where p.source_id = '{{ source_name }}.{{ table_name }}')
    {%- endif -%}
{%- endmacro %}


{% macro cdc_upper_bound(source_name, table_name, change_expression='_dms_cdc_timestamp') -%}
    {#-

    This computes whether a CDC row is visible for this run. That is, whether it is committed
    at or before the `pending` value recorded at the run start. It is effectively the upper
    bound on what to load.

    -#}
    {%- set pending = cdc_watermark_value(source_name, table_name, 'pending') -%}
    (({{ change_expression }}) <= {{ pending }} or {{ pending }} is null)
{%- endmacro %}


{% macro cdc_window(source_name, table_name, change_expression='_dms_cdc_timestamp') -%}
    {#-

    This computes whether a CDC row is in this run's load window. That is, whether it is
    committed after the `position` and before `pending`.

    Strictly speaking, we don't have to have an upper bound to the window, as deduplication
    would take care of any records loaded more than once. However, it falls out conveniently
    from having `pending`, and it means that every model in a run reads the same rows. This
    is important to prevent run failures that result in models where the dependency is not
    visible yet for a row, causing a constraint error, such as with  `sat_s3object_fm_current`.
    Windows can overlap by `cdc_position_margin_minutes`, which deduplication handles.

    -#}
    {%- set position = cdc_watermark_value(source_name, table_name, 'position') -%}
    ((({{ change_expression }}) > {{ position }} or {{ position }} is null)
        and {{ cdc_upper_bound(source_name, table_name, change_expression) }})
{%- endmacro %}


{% macro cdc_bound(source_name, table_name, change_expression='_dms_cdc_timestamp') -%}
    {#-

    This is a convenience to compute either the window or the upper bound only, because
    non-incremental loads don't need a window, and only benefit from the upper bound.

    -#}
    {%- if is_incremental() -%}
        {{ cdc_window(source_name, table_name, change_expression) }}
    {%- else -%}
        {{ cdc_upper_bound(source_name, table_name, change_expression) }}
    {%- endif -%}
{%- endmacro %}


{% macro load_bound(change_expression='load_datetime') -%}
    {#-

    This is the bound for the `load_datetime` for models that don't use the `_dms_cdc_timestamp`.
    That is, it determines which rows to load for all dbt models themselves, rather than CDC
    sources.

    Passing in  `--vars '{"reread_from": "<timestamp>"}'` is useful if an operation ever wants
    to manually read only rows from a certain timepoint. It overrides the lower bound, and reads
    all rows with a `load_datetime` after `reread_from`, which can be used to repair rows. The
    bound is strict, so it should be before the `load_datetime` of the first row to repair.

    -#}
    {%- if is_incremental() -%}
        {%- if var('reread_from', none) -%}
            {%- set lower_bound = "cast('" ~ var('reread_from') ~ "' as timestamptz)" -%}
        {%- else -%}
            {%- set lower_bound = '(select max(load_datetime) from ' ~ this ~ ')' -%}
        {%- endif -%}
        (({{ change_expression }}) > {{ lower_bound }} or {{ lower_bound }} is null)
    {%- else -%}
        true
    {%- endif -%}
{%- endmacro %}
