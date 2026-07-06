{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='experiment_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='experiment_hk',
        sort=['experiment_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# to the dbt run command. Default is false.                    #}
{# Priority order:                                              #}
{#   spreadsheet__library_tracking_metadata                     #}
{#   > data_portal_labmetadata                                  #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select distinct trim(experiment_id) as experiment_id,
        'data_portal_labmetadata' as record_source
    from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}

),

legacy_cleaned as (

    select * from legacy_source
    where experiment_id is not null
      and experiment_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Spreadsheet PSA layer — incremental watermark on             #}
{# load_datetime from the PSA layer.                            #}
{# ============================================================ #}

spreadsheet_source as (

{% else %}

with spreadsheet_source as (

{% endif %}

    select distinct trim(experiment_id) as experiment_id,
        'spreadsheet__library_tracking_metadata' as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select * from spreadsheet_source
    where experiment_id is not null
      and experiment_id <> ''

),

{# ============================================================ #}
{# MERGED                                                       #}
{# Single authoritative deduplication step across all sources.  #}
{# Partitions on experiment_id with full priority ordering.     #}
{# Legacy runs first to establish record_source and             #}
{# load_datetime. Active source appended after — overlapping    #}
{# keys will simply update last_seen_datetime via merge.        #}
{# ============================================================ #}

merged as (

    {% if var('load_legacy', false) %}
    select experiment_id, record_source
    from (
        select
            experiment_id,
            record_source,
            row_number() over (
                partition by experiment_id
                order by case record_source
                    when 'spreadsheet__library_tracking_metadata' then 1
                    when 'data_portal_labmetadata'                then 2
                    else 3
                end
            ) as rn
        from (
            select experiment_id, record_source from legacy_cleaned
            union all
            select experiment_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select experiment_id, record_source from active_cleaned
    {% endif %}

),

transformed as (

    select
        sha2(experiment_id::varchar, 256)           as experiment_hk,
        experiment_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from merged

),

final as (

    select
        cast(experiment_hk      as char(64))       as experiment_hk,
        cast(experiment_id      as varchar(255))   as experiment_id,
        cast(load_datetime      as timestamptz)    as load_datetime,
        cast(record_source      as varchar(100))   as record_source,
        cast(last_seen_datetime as timestamptz)    as last_seen_datetime
    from transformed

)

select * from final
