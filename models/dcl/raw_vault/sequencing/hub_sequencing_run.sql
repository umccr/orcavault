{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sequencing_run_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# to the dbt run command. Default is false.                    #}
{# Priority order:                                              #}
{#   data_portal_sequencerun > data_portal_sequence             #}
{#   > data_portal_libraryrun > data_portal_limsrow             #}
{#   > spreadsheet__google_lims                                 #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select instrument_run_id as sequencing_run_id, 'data_portal_sequencerun'  as record_source from {{ source('data_portal', 'legacy_data_portal_sequencerun') }}
    union all
    select instrument_run_id as sequencing_run_id, 'data_portal_sequence'     as record_source from {{ source('data_portal', 'legacy_data_portal_sequence') }}
    union all
    select instrument_run_id as sequencing_run_id, 'data_portal_libraryrun'   as record_source from {{ source('data_portal', 'legacy_data_portal_libraryrun') }}
    union all
    select instrument_run_id as sequencing_run_id, 'data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select illumina_id        as sequencing_run_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select * from legacy_source
    where sequencing_run_id is not null
      and sequencing_run_id <> ''

),

{# ============================================================ #}
{# CDC BLOCK (daily incremental)                                #}
{# Queries only differential records beyond the warehouse's     #}
{# known horizon (max load_datetime from the Hub).              #}
{# ============================================================ #}

cdc_source as (

{% else %}

with cdc_source as (

{% endif %}

    select distinct
        instrument_run_id as sequencing_run_id,
        'orcabus_sequence_run_manager' as record_source
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_cleaned as (

    select * from cdc_source
    where sequencing_run_id is not null
      and sequencing_run_id <> ''

),

{# ============================================================ #}
{# MERGED                                                       #}
{# Single authoritative deduplication step across all sources.  #}
{# Partitions on sequencing_run_id with full priority ordering. #}
{# Legacy runs first to establish record_source and             #}
{# load_datetime. CDC appended after — overlapping keys will    #}
{# simply update last_seen_datetime via merge strategy.         #}
{# ============================================================ #}

merged as (

    {% if var('load_legacy', false) %}
    select sequencing_run_id, record_source
    from (
        select
            sequencing_run_id,
            record_source,
            row_number() over (
                partition by sequencing_run_id
                order by case record_source
                    when 'data_portal_sequencerun'      then 1
                    when 'data_portal_sequence'         then 2
                    when 'data_portal_libraryrun'       then 3
                    when 'data_portal_limsrow'          then 4
                    when 'spreadsheet__google_lims'     then 5
                    when 'orcabus_sequence_run_manager' then 6
                    else 7
                end
            ) as rn
        from (
            select sequencing_run_id, record_source from legacy_cleaned
            union all
            select sequencing_run_id, record_source from cdc_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select sequencing_run_id, record_source from cdc_cleaned
    {% endif %}

),

transformed as (

    select
        sha2(sequencing_run_id::varchar, 256)       as sequencing_run_hk,
        sequencing_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from merged

),

final as (

    select
        cast(sequencing_run_hk  as char(64))       as sequencing_run_hk,
        cast(sequencing_run_id  as varchar(255))   as sequencing_run_id,
        cast(load_datetime      as timestamptz)    as load_datetime,
        cast(record_source      as varchar(255))   as record_source,
        cast(last_seen_datetime as timestamptz)    as last_seen_datetime
    from transformed

)

select * from final
