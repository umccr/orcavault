{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='append_new_columns',
        full_refresh=var('redcap_case_full_refresh', false)
    )
}}

{#
    Persistent history of the REDCap case records.

    The column list is read from tsa.redcap__case at run time, so a column added to TSA flows into PSA
    without editing this model. on_schema_change='append_new_columns' then adds that column to the PSA table.

    Every source column is compared with the latest persisted version of the same request_id (EXCEPT), so
    any changed value appends the changed record as a new version, including a value that reverts to an
    earlier state. Unchanged records are skipped. Records where every column is null or empty are ignored.
    Exact duplicate rows within one snapshot are removed (select distinct). Records are never deleted, so a
    request_id that disappears from TSA keeps its last version.
    load_datetime and record_source are PSA metadata and never take part in the comparison.

    full_refresh is var-gated so a project-wide --full-refresh cannot discard this history. Rebuild
    deliberately with:
        dbt run -s redcap__case --vars '{redcap_case_full_refresh: true}'
    A rebuild is lossless only while TSA still carries every source row.

    New TSA column handling:
      - The new column is not in {{ this }} yet when this SQL runs (dbt adds it after the query is built),
        so the history side of the EXCEPT selects NULL for it.
      - Column all null in TSA: matches the NULL history value, nothing is appended.
      - Column filled for a record: differs from NULL, so the record is appended as a new version.
        Older versions keep NULL in that column, which preserves history.
#}

{% set src = source('tsa', 'redcap__case') %}
{% set managed = ['load_datetime', 'record_source'] %}

{% set columns = [] %}
{% set column_types = {} %}
{% set target_names = [] %}
{% if execute %}
    {% for c in adapter.get_columns_in_relation(src) %}
        {% if c.name | lower not in managed %}
            {% do columns.append(c.name | lower) %}
            {% do column_types.update({c.name | lower: c.data_type}) %}
        {% endif %}
    {% endfor %}

    {% if is_incremental() %}
        {% for c in adapter.get_columns_in_relation(this) %}
            {% do target_names.append(c.name | lower) %}
        {% endfor %}
    {% endif %}
{% endif %}

with source as (

    select distinct
        {% for col in columns %}
        {{ adapter.quote(col) }}{{ ',' if not loop.last }}
        {% endfor %}
    from
        {{ src }}
    -- Skip records where every column is null or empty.
    where
        coalesce(
            {% for col in columns %}
            nullif(trim(cast({{ adapter.quote(col) }} as varchar)), ''){{ ',' if not loop.last }}
            {% endfor %}
        ) is not null

),

differentiated as (

    select
        *
    from
        source
    {% if is_incremental() %}
    -- EXCEPT compares every column and treats nulls as equal, so only new or changed records remain.
    -- Compared against the latest stored version of each request only, so a value that reverts to an
    -- earlier state (A -> B -> A) is appended again. Columns not yet in the PSA table are compared as NULL.
    except
    select
        {% for col in columns %}
        {% if col in target_names %}
        {{ adapter.quote(col) }}{{ ',' if not loop.last }}
        {% else %}
        cast(null as {{ column_types[col] }}) as {{ adapter.quote(col) }}{{ ',' if not loop.last }}
        {% endif %}
        {% endfor %}
    from (
        select
            *,
            row_number() over (
                partition by request_id
                order by load_datetime desc
            ) as _rn
        from
            {{ this }}
    )
    where
        _rn = 1
    {% endif %}

),

transformed as (

    select
        *,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        cast('redcap__case' as varchar(255)) as record_source
    from
        differentiated

),

final as (

    select * from transformed

)

select * from final
