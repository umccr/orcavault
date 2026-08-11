{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['effective_to', 'is_current'],
        on_schema_change='fail',
        dist='library_owner_hk',
        sort=['library_owner_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# ============================================================ #}

with incremental as (

    select distinct library_hk
    from {{ ref('link_library_ownership') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

history as (

    select
        psa.library_id                                  as library_id,
        psa.project_owner                               as owner_id,
        cast(psa.load_datetime as timestamptz)          as association_date,
        psa.record_source                               as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }} psa
    inner join incremental i
        on i.library_hk = sha2(psa.library_id::varchar, 256)
    where psa.library_id is not null
      and psa.library_id <> ''
      and psa.project_owner is not null
      and psa.project_owner <> ''

    {% if var('load_legacy', false) %}
    union all

    select
        gg.library_id                                   as library_id,
        gg.project_owner                                as owner_id,
        cast(gg.load_datetime as timestamptz)           as association_date,
        gg.record_source                                as record_source
    from {{ ref('spreadsheet__google_lims') }} gg
    inner join incremental i
        on i.library_hk = sha2(gg.library_id::varchar, 256)
    where gg.library_id is not null
      and gg.library_id <> ''
      and gg.project_owner is not null
      and gg.project_owner <> ''
    {% endif %}

),

deduped as (

    select
        sha2(library_id::varchar, 256)                  as library_hk,
        sha2(owner_id::varchar, 256)                    as owner_hk,
        library_id,
        owner_id,
        min(association_date)                           as association_date,
        max(record_source)                              as record_source
    from history
    where library_id is not null
      and library_id <> ''
      and owner_id is not null
      and owner_id <> ''
    group by
        library_id,
        owner_id

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
        {{ generate_hash_diff(['owner_hk', 'library_hk']) }}
                                                        as library_owner_hk,
        cast('{{ run_started_at }}' as timestamptz)     as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'library_id',
            'owner_id'
        ]) }}                                           as hash_diff,
        library_id,
        owner_id,
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
        cast(library_owner_hk       as char(64))        as library_owner_hk,
        cast(load_datetime          as timestamptz)     as load_datetime,
        cast(record_source          as varchar(100))    as record_source,
        cast(hash_diff              as char(64))        as hash_diff,
        cast(library_id             as varchar(255))    as library_id,
        cast(owner_id               as varchar(255))    as owner_id,
        cast(effective_from         as timestamptz)     as effective_from,
        cast(effective_to           as timestamptz)     as effective_to,
        cast(is_current             as smallint)        as is_current
    from transformed

)

select * from final
