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
        cast("timestamp" as date)   as lims_timestamp,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        illumina_id,
        record_source
    from {{ ref('spreadsheet__google_lims') }}
    where library_id is not null
      and library_id <> ''

),

deduped as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by library_id, lims_timestamp
                order by lims_timestamp desc, illumina_id desc, workflow desc
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
            'lims_timestamp',
            'workflow',
            'phenotype',
            'type',
            'assay',
            'quality',
            'source'
        ]) }}                                       as hash_diff,
        lims_timestamp,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source
    from deduped

),

final as (

    select
        cast(library_hk     as char(64))         as library_hk,
        cast(load_datetime  as timestamptz)      as load_datetime,
        cast(record_source  as varchar(100))     as record_source,
        cast(hash_diff      as char(64))         as hash_diff,
        cast(lims_timestamp as date)             as lims_timestamp,
        cast(workflow       as varchar(255))     as workflow,
        cast(phenotype      as varchar(255))     as phenotype,
        cast(type           as varchar(255))     as type,
        cast(assay          as varchar(255))     as assay,
        cast(quality        as varchar(255))     as quality,
        cast(source         as varchar(255))     as source
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
    cast(null as char(64))      as library_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as date)          as lims_timestamp,
    cast(null as varchar(255))  as workflow,
    cast(null as varchar(255))  as phenotype,
    cast(null as varchar(255))  as type,
    cast(null as varchar(255))  as assay,
    cast(null as varchar(255))  as quality,
    cast(null as varchar(255))  as source
where 1 = 0

{% endif %}
