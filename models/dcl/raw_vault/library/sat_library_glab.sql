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

    select distinct
        record_source,
        load_datetime,
        library_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    where library_id is not null
      and library_id <> ''
    {% if is_incremental() %}
      and load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by library_id
                order by load_datetime desc, phenotype
            ) as rn
        from source
    ) t
    where rn = 1

),

transformed as (

    select
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'workflow',
            'phenotype',
            'type',
            'assay',
            'quality',
            'source',
            'truseq_index'
        ]) }}                                       as hash_diff,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index
    from deduped

),

final as (

    select
        cast(library_hk     as char(64))         as library_hk,
        cast(load_datetime  as timestamptz)      as load_datetime,
        cast(record_source  as varchar(100))     as record_source,
        cast(hash_diff      as char(64))         as hash_diff,
        cast(workflow       as varchar(255))     as workflow,
        cast(phenotype      as varchar(255))     as phenotype,
        cast(type           as varchar(255))     as type,
        cast(assay          as varchar(255))     as assay,
        cast(quality        as varchar(255))     as quality,
        cast(source         as varchar(255))     as source,
        cast(truseq_index   as varchar(255))     as truseq_index
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
