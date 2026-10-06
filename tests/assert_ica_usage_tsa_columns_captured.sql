{#
    PSA is meant to be a faithful mirror of tsa.spreadsheet__ica_usage_report, but its projection enumerates
    columns explicitly, and on_schema_change only ever compares a model against its own target table. A column
    Glue adds to TSA is therefore dropped with a green build. That is how the seven BioInsight Core columns
    went unnoticed from the 2026-05 report until 2026-09.

    Returns one row per TSA column the PSA table does not carry. The fix is always to add the column to
    models/psa/spreadsheet__ica_usage_report.sql with a deliberate type, never to relax this test.

    Severity is warn, not error: an uncaptured column leaves the history incomplete rather than wrong, and
    halting the cost mart over a new Illumina column is disproportionate. Raise it to error if the balance
    changes, for instance once TSA no longer holds every source row and a rebuild can no longer recover.
#}

{{ config(severity='warn') }}

{%- set src = source('tsa', 'spreadsheet__ica_usage_report') -%}
{%- set psa = ref('spreadsheet__ica_usage_report') -%}

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

select
    source_columns.column_name as uncaptured_tsa_column
from
    source_columns
where not exists (
    select 1
    from target_columns
    where target_columns.column_name = source_columns.column_name
)
