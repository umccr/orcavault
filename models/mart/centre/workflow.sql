{{
    config(
        on_schema_change='fail',
        dist='portal_run_id',
        sort=['portal_run_id', 'library_id', 'workflow_start']
    )
}}

{# Note - See `dcl.sat_workflow_run` CTE block `cdc_state_latest` for tuning the precision of workflow #}
{# start and end time aggregation logic from the upstream(s). Mart simply consume this summarization.  #}

with linked as (

    select distinct
        hw.portal_run_id                                    as portal_run_id,
        hl.library_id                                       as library_id
    from {{ ref('hub_workflow_run') }} hw
        full join {{ ref('link_library_workflow_run') }} lnk
            on lnk.workflow_run_hk = hw.workflow_run_hk
        full join {{ ref('hub_library') }} hl
            on lnk.library_hk = hl.library_hk

),

merged as (

    select
        hub.portal_run_id,
        sat.workflow_name,
        sat.workflow_version,
        sat.workflow_run_status,
        sat.workflow_run_start,
        sat.workflow_run_end,
        sat.workflow_run_comment
    from {{ ref('hub_workflow_run') }} hub
        join {{ ref('sat_workflow_run') }} sat
            on sat.workflow_run_hk = hub.workflow_run_hk
    where sat.is_deleted = 0

),

transformed as (

    select
        linked.library_id                                   as library_id,
        merged.portal_run_id                                as portal_run_id,
        merged.workflow_name                                as workflow_name,
        merged.workflow_version                             as workflow_version,
        upper(merged.workflow_run_status)                   as workflow_status,
        merged.workflow_run_start                           as workflow_start,
        merged.workflow_run_end                             as workflow_end,
        extract(
            epoch from (
                cast(merged.workflow_run_end as timestamp) - cast(merged.workflow_run_start as timestamp)
            )
        )                                                   as workflow_duration,
        merged.workflow_run_comment                         as workflow_comment
    from merged
        join linked on linked.portal_run_id = merged.portal_run_id

),

final as (

    select
        cast(portal_run_id      as char(16))        as portal_run_id,
        cast(library_id         as varchar(255))    as library_id,
        cast(workflow_name      as varchar(255))    as workflow_name,
        cast(workflow_version   as varchar(255))    as workflow_version,
        cast(workflow_status    as varchar(255))    as workflow_status,
        cast(workflow_start     as timestamptz)     as workflow_start,
        cast(workflow_end       as timestamptz)     as workflow_end,
        cast(workflow_duration  as numeric(12,4))   as workflow_duration,
        cast(workflow_comment   as varchar(65535))  as workflow_comment
    from transformed
    order by portal_run_id desc nulls last, library_id desc

)

select * from final
