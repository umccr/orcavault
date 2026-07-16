{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Frozen source — do not re-run after initial load.            #}
{# NOTE: "input" and "output" columns skipped — JSON content    #}
{# requires dedicated pre-processing pipeline before ingestion. #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with source as (

    select distinct
        portal_run_id,
        id,
        wfr_name,
        type_name,
        wfr_id,
        wfl_id,
        wfv_id,
        version,
        cast(start as timestamptz)      as start_datetime,
        cast("end" as timestamptz)      as end_datetime,
        end_status,
        notified,
        sequence_run_id,
        batch_run_id
    from {{ source('data_portal', 'legacy_data_portal_workflow') }}
    where portal_run_id is not null
      and portal_run_id <> ''

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'legacy_data_portal_workflow'               as record_source,
        {{ generate_hash_diff([
            'id',
            'wfr_name',
            'type_name',
            'wfr_id',
            'wfl_id',
            'wfv_id',
            'version',
            'start_datetime',
            'end_datetime',
            'end_status',
            'notified',
            'sequence_run_id',
            'batch_run_id'
        ]) }}                                       as hash_diff,
        id,
        wfr_name,
        type_name,
        wfr_id,
        wfl_id,
        wfv_id,
        version,
        start_datetime,
        end_datetime,
        end_status,
        notified,
        sequence_run_id,
        batch_run_id
    from source

),

final as (

    select
        cast(workflow_run_hk    as char(64))         as workflow_run_hk,
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(hash_diff          as char(64))         as hash_diff,
        cast(id                 as bigint)           as id,
        cast(wfr_name           as varchar(255))     as wfr_name,
        cast(type_name          as varchar(100))     as type_name,
        cast(wfr_id             as varchar(255))     as wfr_id,
        cast(wfl_id             as varchar(255))     as wfl_id,
        cast(wfv_id             as varchar(255))     as wfv_id,
        cast(version            as varchar(100))     as version,
        cast(start_datetime     as timestamptz)      as start_datetime,
        cast(end_datetime       as timestamptz)      as end_datetime,
        cast(end_status         as varchar(100))     as end_status,
        cast(notified           as smallint)         as notified,
        cast(sequence_run_id    as bigint)           as sequence_run_id,
        cast(batch_run_id       as bigint)           as batch_run_id
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
    cast(null as char(64))      as workflow_run_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as bigint)        as id,
    cast(null as varchar(255))  as wfr_name,
    cast(null as varchar(100))  as type_name,
    cast(null as varchar(255))  as wfr_id,
    cast(null as varchar(255))  as wfl_id,
    cast(null as varchar(255))  as wfv_id,
    cast(null as varchar(100))  as version,
    cast(null as timestamptz)   as start_datetime,
    cast(null as timestamptz)   as end_datetime,
    cast(null as varchar(100))  as end_status,
    cast(null as smallint)      as notified,
    cast(null as bigint)        as sequence_run_id,
    cast(null as bigint)        as batch_run_id
where 1 = 0

{% endif %}
