{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='library_hk',
        sort=['library_hk', 'load_datetime']
    )
}}

with source as (

    select
        library_id,
        orcabus_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        op,
        _dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_library') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cleaned as (

    select
        trim(regexp_replace(library_id, '[\n\r]+', ''))     as library_id,
        trim(regexp_replace(orcabus_id, '[\n\r]+', ''))     as orcabus_id,
        trim(regexp_replace(workflow, '[\n\r]+', ''))       as workflow,
        trim(regexp_replace(phenotype, '[\n\r]+', ''))      as phenotype,
        trim(regexp_replace(type, '[\n\r]+', ''))           as type,
        trim(regexp_replace(assay, '[\n\r]+', ''))          as assay,
        trim(regexp_replace(quality, '[\n\r]+', ''))        as quality,
        op,
        _dms_cdc_timestamp
    from source

),

transformed as (

    select
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'orcabus_metadata_manager'                  as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'workflow',
            'phenotype',
            'type',
            'assay',
            'quality',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
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
                order by library_hk
            ) as rn
        from transformed
    ) t
    where rn = 1

),

final as (

    select
        cast(library_hk         as char(64))         as library_hk,
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(hash_diff          as char(64))         as hash_diff,
        cast(orcabus_id         as char(26))         as orcabus_id,
        cast(workflow           as varchar(255))     as workflow,
        cast(phenotype          as varchar(255))     as phenotype,
        cast(type               as varchar(255))     as type,
        cast(assay              as varchar(255))     as assay,
        cast(quality            as varchar(255))     as quality,
        cast(op                 as char(1))          as op,
        cast(_dms_cdc_timestamp as timestamptz)      as _dms_cdc_timestamp
    from deduped
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = deduped.hash_diff
    )
    {% endif %}

)

select * from final
