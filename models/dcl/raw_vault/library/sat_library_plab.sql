{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='library_hk',
        sort=['library_hk', 'load_datetime']
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
        library_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseqindex
    from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}
    where library_id is not null
      and library_id <> ''

),

cleaned as (

    select
        trim(regexp_replace(library_id, '[\n\r]+', ''))     as library_id,
        trim(regexp_replace(workflow, '[\n\r]+', ''))       as workflow,
        trim(regexp_replace(phenotype, '[\n\r]+', ''))      as phenotype,
        trim(regexp_replace(type, '[\n\r]+', ''))           as type,
        trim(regexp_replace(assay, '[\n\r]+', ''))          as assay,
        trim(regexp_replace(quality, '[\n\r]+', ''))        as quality,
        trim(regexp_replace(source, '[\n\r]+', ''))         as source,
        trim(regexp_replace(truseqindex, '[\n\r]+', ''))    as truseqindex
    from source

),

transformed as (

    select
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'legacy_data_portal_labmetadata'            as record_source,
        {{ generate_hash_diff([
            'workflow',
            'phenotype',
            'type',
            'assay',
            'quality',
            'source',
            'truseqindex'
        ]) }}                                       as hash_diff,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseqindex
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
        cast(truseqindex    as varchar(255))     as truseqindex
    from deduped
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = deduped.hash_diff
    )
    {% endif %}

)

select * from final

{% else %}

{# ============================================================ #}
{# No-op on daily runs — legacy source is frozen.               #}
{# ============================================================ #}

select
    cast(null as char(64))      as library_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as varchar(255))  as workflow,
    cast(null as varchar(255))  as phenotype,
    cast(null as varchar(255))  as type,
    cast(null as varchar(255))  as assay,
    cast(null as varchar(255))  as quality,
    cast(null as varchar(255))  as source,
    cast(null as varchar(255))  as truseqindex
where 1 = 0

{% endif %}
