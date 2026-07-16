{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='project_hk',
        sort=['project_hk', 'load_datetime']
    )
}}

with source as (

    select
        project_id,
        orcabus_id,
        name,
        description,
        op,
        _dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_project') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cleaned as (

    select
        trim(regexp_replace(project_id,   '[\n\r]+', ''))  as project_id,
        trim(regexp_replace(orcabus_id,   '[\n\r]+', ''))  as orcabus_id,
        trim(regexp_replace(name,         '[\n\r]+', ''))  as name,
        trim(regexp_replace(description,  '[\n\r]+', ''))  as description,
        op,
        _dms_cdc_timestamp
    from source

),

transformed as (

    select
        sha2(project_id::varchar, 256)              as project_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'orcabus_metadata_manager'                  as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'name',
            'description',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        name,
        description,
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
                order by project_hk
            ) as rn
        from transformed
    ) t
    where rn = 1

),

final as (

    select
        cast(project_hk         as char(64))         as project_hk,
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(hash_diff          as char(64))         as hash_diff,
        cast(orcabus_id         as char(26))         as orcabus_id,
        cast(name               as varchar(255))     as name,
        cast(description        as varchar(255))     as description,
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
