{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='internal_subject_hk',
        sort=['internal_subject_hk', 'load_datetime']
    )
}}

with source as (

    select
        individual_id   as internal_subject_id,
        orcabus_id,
        source,
        op,
        _dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_individual') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cleaned as (

    select
        trim(regexp_replace(internal_subject_id, '[\n\r]+', ''))    as internal_subject_id,
        trim(regexp_replace(orcabus_id, '[\n\r]+', ''))             as orcabus_id,
        trim(regexp_replace(source, '[\n\r]+', ''))                 as source,
        op,
        _dms_cdc_timestamp
    from source

),

transformed as (

    select
        sha2(internal_subject_id::varchar, 256)     as internal_subject_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'orcabus_metadata_manager'                  as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'source',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        source,
        op,
        _dms_cdc_timestamp
    from cleaned

),

deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by hash_diff
                order by internal_subject_hk
            ) as rn
        from transformed
    ) t
    where rn = 1

),

final as (

    select
        cast(internal_subject_hk    as char(64))         as internal_subject_hk,
        cast(load_datetime          as timestamptz)      as load_datetime,
        cast(record_source          as varchar(100))     as record_source,
        cast(hash_diff              as char(64))         as hash_diff,
        cast(orcabus_id             as char(26))         as orcabus_id,
        cast(source                 as varchar(255))     as source,
        cast(op                     as char(1))          as op,
        cast(_dms_cdc_timestamp     as timestamptz)      as _dms_cdc_timestamp
    from deduped
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = deduped.hash_diff
    )
    {% endif %}

)

select * from final
