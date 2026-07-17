{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='library_workflow_run_hk',
        sort=['library_workflow_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Three-way join across legacy portal workflow tables.         #}
{# Priority order:                                              #}
{#   data_portal_workflow > orcabus_workflow_manager            #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select distinct
        wfr.portal_run_id,
        lbr.library_id,
        'legacy_data_portal_libraryrun_workflows' as record_source
    from {{ source('data_portal', 'legacy_data_portal_workflow') }} wfr
        join {{ source('data_portal', 'legacy_data_portal_libraryrun_workflows') }} lnk
            on lnk.workflow_id = wfr.id
        join {{ source('data_portal', 'legacy_data_portal_libraryrun') }} lbr
            on lbr.id = lnk.libraryrun_id

),

legacy_cleaned as (

    select distinct portal_run_id, library_id, record_source
    from legacy_source
    where portal_run_id is not null
      and portal_run_id <> ''
      and library_id is not null
      and library_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# CDC joins workflow_manager_workflowrun to                    #}
{# workflow_manager_libraryassociation to                       #}
{# workflow_manager_library.                                    #}
{# Incremental watermark on libraryassociation._dms_cdc_timestamp#}
{# ============================================================ #}

cdc_source as (

{% else %}

with cdc_source as (

{% endif %}

    select distinct
        wfr.portal_run_id,
        lib.library_id,
        'orcabus_workflow_manager'                  as record_source
    from {{ source('orcabus_workflow_manager', 'workflow_manager_libraryassociation') }} lnk
        join {{ source('orcabus_workflow_manager', 'workflow_manager_workflowrun') }} wfr
            on wfr.orcabus_id = lnk.workflow_run_id
        join {{ source('orcabus_workflow_manager', 'workflow_manager_library') }} lib
            on lib.orcabus_id = lnk.library_id
    {% if is_incremental() %}
    where lnk._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select distinct portal_run_id, library_id, record_source
    from cdc_source
    where portal_run_id is not null
      and portal_run_id <> ''
      and library_id is not null
      and library_id <> ''

),

merged as (

    {% if var('load_legacy', false) %}
    select portal_run_id, library_id, record_source
    from (
        select
            portal_run_id,
            library_id,
            record_source,
            row_number() over (
                partition by portal_run_id, library_id
                order by case record_source
                    when 'legacy_data_portal_libraryrun_workflows'        then 1
                    when 'orcabus_workflow_manager'                       then 2
                    else 3
                end
            ) as rn
        from (
            select portal_run_id, library_id, record_source from legacy_cleaned
            union all
            select portal_run_id, library_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select portal_run_id, library_id, record_source from active_cleaned
    {% endif %}

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source
    from merged

),

final as (

    select
        cast({{ generate_hash_diff(['workflow_run_hk', 'library_hk']) }}
                                        as char(64))     as library_workflow_run_hk,
        cast(workflow_run_hk            as char(64))     as workflow_run_hk,
        cast(library_hk                 as char(64))     as library_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.workflow_run_hk = transformed.workflow_run_hk
          and t.library_hk = transformed.library_hk
    )
    {% endif %}

)

select * from final
