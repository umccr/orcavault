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

    {#

    This lookup gets every workflow run up to `pending`, not only those in this dbt run's window.
    A comment in the window can belong to a workflow run committed in an earlier dbt run,
    and the inner join below would drop it if the lookup didn't have that workflow run.

    Its newest commit time lets the `cdc_window` reprocess a comment where the workflow run
    arrived after it, since the join would have dropped that comment otherwise.

    #}

    select
        orcabus_id,
        portal_run_id,
        max(_dms_cdc_timestamp) as _dms_cdc_timestamp
    from {{ source('orcabus_workflow_manager', 'workflow_manager_workflowrun') }}
    where {{ cdc_upper_bound('orcabus_workflow_manager', 'workflow_manager_workflowrun') }}
    group by orcabus_id, portal_run_id

),

source as (

    {# ======================================================== #}
    {# All comment records within the incremental window.       #}
    {# No daily dedup — raw vault keeps full comment history.   #}
    {# Business vault handles latest comment derivation.        #}
    {# ======================================================== #}

    select
        wfr.portal_run_id,
        cmt.orcabus_id,
        cmt.text            as comment,
        cmt.created_at,
        cmt.created_by,
        cmt.updated_at,
        cmt.is_deleted,
        cmt.workflow_run_id,
        cmt.analysis_run_id,
        cmt.severity,
        cmt.op,
        cmt._dms_cdc_timestamp
    from {{ source('orcabus_workflow_manager', 'workflow_manager_comment') }} cmt
        join wfr_lookup wfr on wfr.orcabus_id = cmt.workflow_run_id
    where {{ cdc_upper_bound('orcabus_workflow_manager', 'workflow_manager_comment', 'cmt._dms_cdc_timestamp') }}
    {% if is_incremental() %}
      and (
          {{ cdc_window('orcabus_workflow_manager', 'workflow_manager_comment', 'cmt._dms_cdc_timestamp') }}
          or {{ cdc_window('orcabus_workflow_manager', 'workflow_manager_workflowrun', 'wfr._dms_cdc_timestamp') }}
      )
    {% endif %}

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'workflow_manager_comment'                  as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'comment',
            'created_at',
            'created_by',
            'updated_at',
            'is_deleted',
            'workflow_run_id',
            'analysis_run_id',
            'severity',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        comment,
        created_at,
        created_by,
        updated_at,
        is_deleted,
        workflow_run_id,
        analysis_run_id,
        severity,
        op,
        _dms_cdc_timestamp
    from source

),

final as (

    select
        cast(workflow_run_hk    as char(64))             as workflow_run_hk,
        cast(load_datetime      as timestamptz)          as load_datetime,
        cast(record_source      as varchar(100))         as record_source,
        cast(hash_diff          as char(64))             as hash_diff,
        cast(orcabus_id         as char(26))             as orcabus_id,
        cast(comment            as varchar(65535))       as comment,
        cast(created_at         as timestamptz)          as created_at,
        cast(created_by         as varchar(100))         as created_by,
        cast(updated_at         as timestamptz)          as updated_at,
        cast(is_deleted         as varchar(100))         as is_deleted,
        cast(workflow_run_id    as char(26))             as workflow_run_id,
        cast(analysis_run_id    as char(26))             as analysis_run_id,
        cast(severity           as varchar(100))         as severity,
        cast(op                 as char(1))              as op,
        cast(_dms_cdc_timestamp as timestamptz)          as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
