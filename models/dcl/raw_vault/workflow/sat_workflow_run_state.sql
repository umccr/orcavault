{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

with wfr_lookup as (

    select distinct
        orcabus_id,
        portal_run_id
    from {{ source('orcabus_workflow_manager', 'workflow_manager_workflowrun') }}

),

source as (

    {# ======================================================== #}
    {# All state records within the incremental window.         #}
    {# No dedup — raw vault keeps full state history.           #}
    {# Business vault handles state transition derivation.      #}
    {# ======================================================== #}

    select
        wfr.portal_run_id,
        stt.orcabus_id,
        stt.status,
        stt.timestamp       as state_timestamp,
        stt.comment,
        stt.payload_id,
        stt.workflow_run_id,
        stt.op,
        stt._dms_cdc_timestamp
    from {{ source('orcabus_workflow_manager', 'workflow_manager_state') }} stt
        join wfr_lookup wfr on wfr.orcabus_id = stt.workflow_run_id
    {% if is_incremental() %}
    where stt._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'workflow_manager_state'                    as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'status',
            'state_timestamp',
            'comment',
            'payload_id',
            'workflow_run_id',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        status,
        state_timestamp,
        comment,
        payload_id,
        workflow_run_id,
        op,
        _dms_cdc_timestamp
    from source

),

final as (

    select
        cast(workflow_run_hk    as char(64))         as workflow_run_hk,
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(hash_diff          as char(64))         as hash_diff,
        cast(orcabus_id         as char(26))         as orcabus_id,
        cast(status             as varchar(255))     as status,
        cast(state_timestamp    as timestamptz)      as state_timestamp,
        cast(comment            as varchar(1024))    as comment,
        cast(payload_id         as char(26))         as payload_id,
        cast(workflow_run_id    as char(26))         as workflow_run_id,
        cast(op                 as char(1))          as op,
        cast(_dms_cdc_timestamp as timestamptz)      as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
