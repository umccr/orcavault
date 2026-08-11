{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['effective_to', 'is_current'],
        on_schema_change='fail',
        dist='library_experiment_hk',
        sort=['library_experiment_hk', 'load_datetime']
    )
}}

with incremental as (

    select distinct library_hk
    from {{ ref('link_library_experiment') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

history as (

    select
        sha2(psa.library_id::varchar, 256)                  as library_hk,
        sha2(psa.experiment_id::varchar, 256)               as experiment_hk,
        psa.library_id                                      as library_id,
        psa.experiment_id                                   as experiment_id,
        min(psa.load_datetime)                              as association_date,
        max(psa.record_source)                              as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }} psa
    inner join incremental i
        on i.library_hk = sha2(psa.library_id::varchar, 256)
    where psa.library_id is not null
      and psa.library_id <> ''
      and psa.experiment_id is not null
      and psa.experiment_id <> ''
    group by
        psa.library_id,
        psa.experiment_id

),

ranked as (

    select
        *,
        row_number() over (
            partition by library_id
            order by association_date desc
        )                                                   as rank
    from history

),

transformed as (

    select
        {{ generate_hash_diff(['experiment_hk', 'library_hk']) }}
                                                            as library_experiment_hk,
        cast('{{ run_started_at }}' as timestamptz)         as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'library_id',
            'experiment_id'
        ]) }}                                               as hash_diff,
        library_id,
        experiment_id,
        cast(association_date as timestamptz)               as effective_from,
        case
            when rank = 1
                then cast('9999-12-31 00:00:00' as timestamptz)
            else
                lag(association_date) over (
                    partition by library_id
                    order by rank
                )
        end                                                 as effective_to,
        case when rank = 1 then 1 else 0 end                as is_current
    from ranked

),

final as (

    select
        cast(library_experiment_hk  as char(64))        as library_experiment_hk,
        cast(load_datetime          as timestamptz)     as load_datetime,
        cast(record_source          as varchar(100))    as record_source,
        cast(hash_diff              as char(64))        as hash_diff,
        cast(library_id             as varchar(255))    as library_id,
        cast(experiment_id          as varchar(255))    as experiment_id,
        cast(effective_from         as timestamptz)     as effective_from,
        cast(effective_to           as timestamptz)     as effective_to,
        cast(is_current             as smallint)        as is_current
    from transformed

)

select * from final
