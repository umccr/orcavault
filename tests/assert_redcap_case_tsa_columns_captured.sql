{#
    PSA mirrors tsa.redcap__case. The model reads its column list from TSA at run time and
    on_schema_change='append_new_columns' adds any new TSA column to the PSA table, so this test is a
    safety net, not the way columns get added.

    Returns one row per TSA column the PSA table does not carry. A row here means the model has not run
    since the column appeared in TSA (run order, or a failed or skipped run), or the PSA table was altered
    by hand. Re-run the model with: dbt run -s redcap__case. Never relax this test.

    Severity is warn, not error: an uncaptured column leaves the history incomplete rather than wrong.
#}

{{ config(severity='warn') }}

{%- set src = source('tsa', 'redcap__case') -%}
{%- set psa = ref('redcap__case') -%}

with source_columns as (

    select distinct lower(column_name) as column_name
    from svv_columns
    where table_schema = '{{ src.schema }}'
      and table_name = '{{ src.identifier }}'

),

target_columns as (

    select distinct lower(column_name) as column_name
    from svv_columns
    where table_schema = '{{ psa.schema }}'
      and table_name = '{{ psa.identifier }}'

)

-- Returns TSA columns with no match in PSA.
-- Left join instead of not exists, because Redshift rejects not exists under --store-failures.
select
    source_columns.column_name as uncaptured_tsa_column
from
    source_columns
    left join target_columns
        on target_columns.column_name = source_columns.column_name
where
    target_columns.column_name is null
