{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

with wfl_lookup as (

    {# ======================================================== #}
    {# Full scan of parent workflow definition table.           #}
    {# low cardinality rows — negligible cost.                  #}
    {# Always full scan — child workflowrun records can         #}
    {# reference any pre-existing workflow definition.          #}
    {# Deduplicate to latest state per workflow orcabus_id.     #}
    {# ======================================================== #}

    select
        orcabus_id          as workflow_orcabus_id,
        name                as workflow_name,
        version             as workflow_version,
        execution_engine    as workflow_execution_engine,
        execution_engine_pipeline_id as workflow_execution_engine_pipeline_id,
        validation_state    as workflow_validation_state,
        code_version        as workflow_code_version
    from (
        select
            *,
            row_number() over (
                partition by orcabus_id
                order by _dms_cdc_timestamp desc
            ) as rn
        from {{ source('orcabus_workflow_manager', 'workflow_manager_workflow') }}
    ) t
    where rn = 1

),

source as (

    {# ======================================================== #}
    {# All workflowrun records within the incremental window.   #}
    {# No dedup — source data rarely duplicates on portal_run_id#}
    {# Business vault handles current state derivation.         #}
    {# ======================================================== #}

    select
        wfr.portal_run_id,
        wfr.orcabus_id,
        wfr.execution_id,
        wfr.workflow_run_name,
        wfr.comment,
        wfr.analysis_run_id,
        wfl.workflow_orcabus_id,
        wfl.workflow_name,
        wfl.workflow_version,
        wfl.workflow_execution_engine,
        wfl.workflow_execution_engine_pipeline_id,
        wfl.workflow_validation_state,
        wfl.workflow_code_version,
        wfr.op,
        wfr._dms_cdc_timestamp
    from {{ source('orcabus_workflow_manager', 'workflow_manager_workflowrun') }} wfr
        join wfl_lookup wfl on wfl.workflow_orcabus_id = wfr.workflow_id
    {% if is_incremental() %}
    where wfr._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'workflow_manager_workflowrun'              as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'execution_id',
            'workflow_run_name',
            'comment',
            'analysis_run_id',
            'workflow_orcabus_id',
            'workflow_name',
            'workflow_version',
            'workflow_execution_engine',
            'workflow_execution_engine_pipeline_id',
            'workflow_validation_state',
            'workflow_code_version',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        execution_id,
        workflow_run_name,
        comment,
        analysis_run_id,
        workflow_orcabus_id,
        workflow_name,
        workflow_version,
        workflow_execution_engine,
        workflow_execution_engine_pipeline_id,
        workflow_validation_state,
        workflow_code_version,
        op,
        _dms_cdc_timestamp
    from source

),

final as (

    select
        cast(workflow_run_hk                        as char(64))         as workflow_run_hk,
        cast(load_datetime                          as timestamptz)      as load_datetime,
        cast(record_source                          as varchar(100))     as record_source,
        cast(hash_diff                              as char(64))         as hash_diff,
        cast(orcabus_id                             as char(26))         as orcabus_id,
        cast(execution_id                           as varchar(255))     as execution_id,
        cast(workflow_run_name                      as varchar(255))     as workflow_run_name,
        cast(comment                                as varchar(65535))   as comment,
        cast(analysis_run_id                        as char(26))         as analysis_run_id,
        cast(workflow_orcabus_id                    as char(26))         as workflow_orcabus_id,
        cast(workflow_name                          as varchar(255))     as workflow_name,
        cast(workflow_version                       as varchar(100))     as workflow_version,
        cast(workflow_execution_engine              as varchar(100))     as workflow_execution_engine,
        cast(workflow_execution_engine_pipeline_id  as varchar(255))     as workflow_execution_engine_pipeline_id,
        cast(workflow_validation_state              as varchar(100))     as workflow_validation_state,
        cast(workflow_code_version                  as varchar(100))     as workflow_code_version,
        cast(op                                     as char(1))          as op,
        cast(_dms_cdc_timestamp                     as timestamptz)      as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
