{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['effective_to', 'is_current'],
        on_schema_change='fail',
        dist='library_external_sample_hk',
        sort=['library_external_sample_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# ============================================================ #}

with incremental as (

    select distinct library_hk
    from {{ ref('link_library_external_sample') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_library as (

    select
        lib.library_id,
        lib.sample_orcabus_id,
        lib._dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_library') }} lib
    inner join incremental i
        on i.library_hk = sha2(lib.library_id::varchar, 256)
    {% if is_incremental() %}
    where lib._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

history as (

    select
        lib.library_id                                  as library_id,
        smp.external_sample_id                          as external_sample_id,
        cast(lib._dms_cdc_timestamp as timestamptz)     as association_date,
        'orcabus_metadata_manager'                      as record_source
    from cdc_library lib
        join {{ source('orcabus_metadata_manager', 'app_sample') }} smp
            on smp.orcabus_id = lib.sample_orcabus_id

    union all

    select
        psa.library_id                                  as library_id,
        psa.external_sample_id                          as external_sample_id,
        cast(psa.load_datetime as timestamptz)          as association_date,
        psa.record_source                               as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }} psa
    inner join incremental i
        on i.library_hk = sha2(psa.library_id::varchar, 256)
    where psa.library_id is not null
      and psa.library_id <> ''
      and psa.external_sample_id is not null
      and psa.external_sample_id <> ''

    {% if var('load_legacy', false) %}
    union all

    select
        gg.library_id                                   as library_id,
        gg.external_sample_id                           as external_sample_id,
        cast(gg.load_datetime as timestamptz)           as association_date,
        gg.record_source                                as record_source
    from {{ ref('spreadsheet__google_lims') }} gg
    inner join incremental i
        on i.library_hk = sha2(gg.library_id::varchar, 256)
    where gg.library_id is not null
      and gg.library_id <> ''
      and gg.external_sample_id is not null
      and gg.external_sample_id <> ''
    {% endif %}

),

deduped as (

    select
        sha2(library_id::varchar, 256)                  as library_hk,
        sha2(external_sample_id::varchar, 256)          as external_sample_hk,
        library_id,
        external_sample_id,
        min(association_date)                           as association_date,
        max(record_source)                              as record_source
    from history
    where library_id is not null
      and library_id <> ''
      and external_sample_id is not null
      and external_sample_id <> ''
    group by
        library_id,
        external_sample_id

),

ranked as (

    select
        *,
        row_number() over (
            partition by library_id
            order by association_date desc
        )                                               as rank
    from deduped

),

transformed as (

    select
        {{ generate_hash_diff(['external_sample_hk', 'library_hk']) }}
                                                        as library_external_sample_hk,
        cast('{{ run_started_at }}' as timestamptz)     as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'library_id',
            'external_sample_id'
        ]) }}                                           as hash_diff,
        library_id,
        external_sample_id,
        cast(association_date as timestamptz)           as effective_from,
        case
            when rank = 1
                then cast('9999-12-31 00:00:00' as timestamptz)
            else
                lag(association_date) over (
                    partition by library_id
                    order by rank
                )
        end                                             as effective_to,
        case when rank = 1 then 1 else 0 end            as is_current
    from ranked

),

final as (

    select
        cast(library_external_sample_hk     as char(64))        as library_external_sample_hk,
        cast(load_datetime                  as timestamptz)     as load_datetime,
        cast(record_source                  as varchar(100))    as record_source,
        cast(hash_diff                      as char(64))        as hash_diff,
        cast(library_id                     as varchar(255))    as library_id,
        cast(external_sample_id             as varchar(255))    as external_sample_id,
        cast(effective_from                 as timestamptz)     as effective_from,
        cast(effective_to                   as timestamptz)     as effective_to,
        cast(is_current                     as smallint)        as is_current
    from transformed

)

select * from final
