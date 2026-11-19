{#
    PSA is meant to mirror tsa.redcap__case, but its projection enumerates columns explicitly, and
    on_schema_change only ever compares a model against its own target table. A field added to the REDCap
    project and picked up by TSA is therefore dropped with a green build.

    Returns one row per TSA column the PSA table does not carry. The fix is to add the column to
    models/psa/redcap__case.sql, never to relax this test. Adding it to the column list changes what the
    EXCEPT compares, so read the note at the top of that model first.

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
