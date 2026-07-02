{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='library_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='library_hk',
        sort=['library_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# to the dbt run command. Default is false.                    #}
{# Priority order:                                              #}
{#   spreadsheet__library_tracking_metadata                     #}
{#   > spreadsheet__google_lims                                 #}
{#   > data_portal_labmetadata > data_portal_limsrow            #}
{#   > orcabus_metadata_manager                                 #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select library_id, 'data_portal_labmetadata'  as record_source from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}
    union all
    select library_id, 'data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select library_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select * from legacy_source
    where library_id is not null
      and library_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Two active sources — spreadsheet PSA layer and CDC.          #}
{# Queries only differential records beyond the warehouse's     #}
{# known horizon (max load_datetime from the Hub).              #}
{# ============================================================ #}

spreadsheet_source as (

{% else %}

with spreadsheet_source as (

{% endif %}

    select distinct
        library_id,
        'spreadsheet__library_tracking_metadata' as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_source as (

    select distinct
        library_id,
        'orcabus_metadata_manager' as record_source
    from {{ source('orcabus_metadata_manager', 'app_library') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select * from spreadsheet_source
    where library_id is not null
      and library_id <> ''
    union all
    select * from cdc_source
    where library_id is not null
      and library_id <> ''

),

{# ============================================================ #}
{# MERGED                                                       #}
{# Single authoritative deduplication step across all sources.  #}
{# Partitions on library_id with full priority ordering.        #}
{# Legacy runs first to establish record_source and             #}
{# load_datetime. Active sources appended after — overlapping   #}
{# keys will simply update last_seen_datetime via merge.        #}
{# ============================================================ #}

merged as (

    {% if var('load_legacy', false) %}
    select library_id, record_source
    from (
        select
            library_id,
            record_source,
            row_number() over (
                partition by library_id
                order by case record_source
                    when 'spreadsheet__library_tracking_metadata' then 1
                    when 'spreadsheet__google_lims'               then 2
                    when 'data_portal_labmetadata'                then 3
                    when 'data_portal_limsrow'                    then 4
                    when 'orcabus_metadata_manager'               then 5
                    else 6
                end
            ) as rn
        from (
            select library_id, record_source from legacy_cleaned
            union all
            select library_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select library_id, record_source
    from (
        select
            library_id,
            record_source,
            row_number() over (
                partition by library_id
                order by case record_source
                    when 'spreadsheet__library_tracking_metadata' then 1
                    when 'orcabus_metadata_manager'               then 2
                    else 3
                end
            ) as rn
        from active_cleaned
    ) t
    where rn = 1
    {% endif %}

),

transformed as (

    select
        sha2(library_id::varchar, 256)              as library_hk,
        library_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from merged

),

final as (

    select
        cast(library_hk         as char(64))       as library_hk,
        cast(library_id         as varchar(255))   as library_id,
        cast(load_datetime      as timestamptz)    as load_datetime,
        cast(record_source      as varchar(255))   as record_source,
        cast(last_seen_datetime as timestamptz)    as last_seen_datetime
    from transformed

)

select * from final
