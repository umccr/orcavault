{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Frozen source — do not re-run after initial load.            #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with source as (

    select
        id,
        bucket,
        "key",
        "size",
        e_tag,
        cast(last_modified_date as timestamptz)             as last_modified_date
    from {{ source('data_portal', 'legacy_data_portal_s3object') }}
    where bucket is not null
      and "key" is not null

),

transformed as (

    select
        {{ generate_s3object_hk('bucket', '"key"') }}       as s3object_hk,
        cast('{{ run_started_at }}' as timestamptz)         as load_datetime,
        'legacy_data_portal_s3object'                       as record_source,
        {{ generate_hash_diff([
            'id',
            '"size"',
            'e_tag',
            'last_modified_date'
        ]) }}                                               as hash_diff,
        id,
        "size",
        e_tag,
        last_modified_date
    from source

),

final as (

    select
        cast(s3object_hk        as char(64))        as s3object_hk,
        cast(load_datetime      as timestamptz)     as load_datetime,
        cast(record_source      as varchar(100))    as record_source,
        cast(hash_diff          as char(64))        as hash_diff,
        cast(id                 as bigint)          as id,
        cast("size"             as bigint)          as "size",
        cast(e_tag              as varchar(255))    as e_tag,
        cast(last_modified_date as timestamptz)     as last_modified_date
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final

{% else %}

{# ============================================================ #}
{# No-op on daily runs — legacy source is frozen.               #}
{# ============================================================ #}

select
    cast(null as char(64))      as s3object_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as bigint)        as id,
    cast(null as bigint)        as "size",
    cast(null as varchar(255))  as e_tag,
    cast(null as timestamptz)   as last_modified_date
where 1 = 0

{% endif %}
