{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sal_library_hk',
        on_schema_change='fail',
        dist='sal_library_hk',
        sort=['sal_library_hk', 'load_datetime']
    )
}}

with source as (

    select
        library_hk      as alias_library_hk,
        library_id      as alias_library_id,
        record_source
    from {{ ref('hub_library') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

filtered as (

    select
        alias_library_hk,
        alias_library_id,
        {{ extract_library_id('alias_library_id') }}    as base_library_id,
        record_source
    from source
    where alias_library_id like '%topup%'
       or alias_library_id like '%rerun%'

),

transformed as (

    select
        sha2(base_library_id::varchar, 256)         as base_library_hk,
        alias_library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        base_library_id,
        alias_library_id
    from filtered

),

final as (

    select
        cast({{ generate_hash_diff(['base_library_hk', 'alias_library_hk']) }}
                                        as char(64))     as sal_library_hk,
        cast(base_library_hk            as char(64))     as base_library_hk,
        cast(alias_library_hk           as char(64))     as alias_library_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source,
        cast(base_library_id            as varchar(255)) as base_library_id,
        cast(alias_library_id           as varchar(255)) as alias_library_id
    from transformed

)

select * from final
