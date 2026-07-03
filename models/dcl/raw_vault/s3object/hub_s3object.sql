{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='s3object_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# to the dbt run command. Default is false.                    #}
{#                                                              #}
{# IMPORTANT: For hub_s3object, legacy and CDC initial loads    #}
{# must be run separately in sequence due to high row counts:   #}
{#   Run 1: normal run (CDC only, full load)                    #}
{#   Run 2: --vars '{"load_legacy": true}' (legacy only)        #}
{#                                                              #}
{# CDC must run first so the incremental watermark is not yet   #}
{# active — all CDC records are loaded without filter.          #}
{# Legacy runs second — overlapping keys update                 #}
{# last_seen_datetime only. CDC record_source is preserved      #}
{# as merge_update_columns does not include record_source.      #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with source as (

    select distinct
        bucket,
        "key",
        'data_portal_s3object' as record_source
    from {{ source('data_portal', 'legacy_data_portal_s3object') }}

),

{% else %}

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# CDC queries only differential records beyond the warehouse's #}
{# known horizon (max load_datetime from the Hub).              #}
{#                                                              #}
{# NOTE: This is the highest volume model in the warehouse.     #}
{# The incremental watermark filter is critical — ensure        #}
{# _dms_cdc_timestamp is indexed on the source table.           #}
{# ============================================================ #}

with source as (

    select distinct
        bucket,
        "key",
        'orcabus_filemanager_s3_object' as record_source
    from {{ source('orcabus_filemanager', 's3_object') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

{% endif %}

cleaned as (

    select * from source
    where bucket is not null
      and bucket <> ''
      and "key" is not null
      and "key" <> ''

),

transformed as (

    select
        sha2('s3://' || bucket || '/' || "key", 256) as s3object_hk,
        bucket,
        "key",
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from cleaned

),

final as (

    select
        cast(s3object_hk        as char(64))         as s3object_hk,
        cast(bucket             as varchar(63))      as bucket,
        cast("key"              as varchar(1024))    as "key",
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(last_seen_datetime as timestamptz)      as last_seen_datetime
    from transformed

)

select * from final
