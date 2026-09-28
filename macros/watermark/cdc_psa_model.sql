{% macro cdc_psa_model(source_name, table_name, partition_expression=none) %}
    {#-
    This macro creates the DMS data source in the PSA by copying the source and appending
    the source path, date and partition. It also captures the initial time for this dbt run
    via the load_datetime.

    This files themselves serve as the basis for watermarking which rows to ingest during
    incremental loading. This macro captures the original source file directly to avoid any
    issues with different times being compared against each other, and ensures that downstream
    models use a consistent load_datetime from here.

    It is essential for this table to be consistent across all data sources which is why it is
    defined as a macro here.
    #}

    {% set source_id = source_name ~ '.' ~ table_name %}
    {% do config(
        materialized='incremental',
        incremental_strategy='append',
        full_refresh=false,
        on_schema_change='append_new_columns',
        meta={'cdc_source_id': source_id}
    ) %}

    {#- Extract the partition date from either the `partition_date` is supplied or the key path. #}
    {% set partition_date %}
        {%- if partition_expression -%}
        to_date(source.{{ partition_expression }}, 'YYYYMMDD')
        {%- else -%}
        to_date(nullif(left(regexp_substr(source."$path", '[0-9]{4}/[0-9]{2}/[0-9]{2}/[^/]+$'), 10), ''), 'YYYY/MM/DD')
        {%- endif -%}
    {% endset %}

    select
        source.*,
        {#- The $path is s3://bucket/key, so max length is 5 + 63 + 1 + 1024 = 1093 #}
        cast(source."$path" as varchar(1093)) as source_file_path,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        '{{ source_name }}_{{ table_name }}'::varchar(100) as record_source,
        {{ partition_date }} as source_partition_date
    from {{ source(source_name, table_name) }} as source
    {% if is_incremental() %}
    {#- This is what ingests the correct files, i.e. everything that hasn't been seen yet. #}
    where not exists (
        select 1
        from {{ this }} as staged
        where staged.source_file_path = source."$path"
    )
    {% endif %}

{% endmacro %}
