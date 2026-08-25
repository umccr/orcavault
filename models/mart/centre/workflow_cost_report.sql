{{
    config(
        materialized='table',
        dist='portal_run_id',
        sort=['portal_run_id', 'ica_project']
    )
}}

with workflow as (

    select
        hub.workflow_run_hk            as workflow_run_hk,
        hub.portal_run_id              as portal_run_id,
        sat.workflow_name              as workflow_name,
        sat.workflow_version           as workflow_version,
        upper(sat.workflow_run_status) as workflow_run_status
    from {{ ref('hub_workflow_run') }} hub
        join {{ ref('sat_workflow_run') }} sat
            on sat.workflow_run_hk = hub.workflow_run_hk
    where sat.is_deleted = 0

),

cost as (

    {#
      ICA usage is normally associated with a project and billed in iCredits.
      Rare non-project usage is retained in an ica_project is null bucket, and
      cost_unit remains in the aggregation grain so null or future units are
      reported separately instead of being combined into an invalid total.
    #}

    select
        ica.workflow_run_hk as workflow_run_hk,
        case
            when ica.usage_context_type = 'Project' then ica.usage_context
            else null
        end as ica_project,
        ica.cost_unit as cost_unit,
        sum(ica.cost) as total_cost,
        sum(
            case
                when ica.is_license_cost = false and ica.category = 'Compute'
                    then ica.cost
            end
        ) as compute_cost,
        sum(
            case
                when ica.is_license_cost = true
                    then ica.cost
            end
        ) as license_cost
    from {{ ref('sat_workflow_run_ica_usage') }} ica
    group by
        ica.workflow_run_hk,
        case
            when ica.usage_context_type = 'Project' then ica.usage_context
            else null
        end,
        ica.cost_unit

),

merged as (

    select
        workflow.portal_run_id             as portal_run_id,
        workflow.workflow_name             as workflow_name,
        workflow.workflow_version          as workflow_version,
        workflow.workflow_run_status       as workflow_status,
        cost.ica_project                   as ica_project,
        cost.cost_unit                     as cost_unit,
        cost.total_cost                    as total_cost,
        cost.compute_cost                  as compute_cost,
        cost.license_cost                  as license_cost
    from cost
        inner join workflow on cost.workflow_run_hk = workflow.workflow_run_hk

),

final as (

    {#
      The reference mart used numeric(10,2). numeric(18,2) preserves monetary
      reporting precision while providing substantially more headroom for
      aggregated workflow costs without requiring a 128-bit Redshift decimal.
    #}

    select
        cast(portal_run_id    as char(16))        as portal_run_id,
        cast(workflow_name    as varchar(255))    as workflow_name,
        cast(workflow_version as varchar(255))    as workflow_version,
        cast(workflow_status  as varchar(255))    as workflow_status,
        cast(total_cost       as numeric(18, 2))  as total_cost,
        cast(compute_cost     as numeric(18, 2))  as compute_cost,
        cast(license_cost     as numeric(18, 2))  as license_cost,
        cast(ica_project      as varchar(255))    as ica_project,
        cast(cost_unit        as varchar(255))    as cost_unit
    from merged

)

select * from final
