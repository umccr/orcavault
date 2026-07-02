{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='workflow_run_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# to the dbt run command. Default is false.                    #}
{# Priority order:                                              #}
{#   data_portal_workflow > workflow_manager_workflowrun        #}
{#   > mdm__workflow_run                                        #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select portal_run_id, 'data_portal_workflow' as record_source
    from {{ source('data_portal', 'legacy_data_portal_workflow') }}

),

legacy_cleaned as (

    select * from legacy_source
    where portal_run_id is not null
      and portal_run_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Two active sources — CDC and MDM seed.                       #}
{# CDC queries only differential records beyond the warehouse's #}
{# known horizon (max load_datetime from the Hub).              #}
{# MDM seed is small static dataset — full scan is acceptable.  #}
{# ============================================================ #}

cdc_source as (

{% else %}

with cdc_source as (

{% endif %}

    select distinct
        portal_run_id,
        'workflow_manager_workflowrun' as record_source
    from {{ source('orcabus_workflow_manager', 'workflow_manager_workflowrun') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

mdm_source as (

    select base_portal_run_id  as portal_run_id, 'mdm__workflow_run' as record_source from {{ ref('mdm__workflow_run') }}
    union all
    select alias_portal_run_id as portal_run_id, 'mdm__workflow_run' as record_source from {{ ref('mdm__workflow_run') }}

),

active_cleaned as (

    select * from cdc_source
    where portal_run_id is not null
      and portal_run_id <> ''
    union all
    select * from mdm_source
    where portal_run_id is not null
      and portal_run_id <> ''

),

{# ============================================================ #}
{# MERGED                                                       #}
{# Single authoritative deduplication step across all sources.  #}
{# Partitions on portal_run_id with full priority ordering.     #}
{# Legacy runs first to establish record_source and             #}
{# load_datetime. Active sources appended after — overlapping   #}
{# keys will simply update last_seen_datetime via merge.        #}
{# ============================================================ #}

merged as (

    {% if var('load_legacy', false) %}
    select portal_run_id, record_source
    from (
        select
            portal_run_id,
            record_source,
            row_number() over (
                partition by portal_run_id
                order by case record_source
                    when 'data_portal_workflow'           then 1
                    when 'workflow_manager_workflowrun'   then 2
                    when 'mdm__workflow_run'              then 3
                    else 4
                end
            ) as rn
        from (
            select portal_run_id, record_source from legacy_cleaned
            union all
            select portal_run_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select portal_run_id, record_source
    from (
        select
            portal_run_id,
            record_source,
            row_number() over (
                partition by portal_run_id
                order by case record_source
                    when 'workflow_manager_workflowrun' then 1
                    when 'mdm__workflow_run'            then 2
                    else 3
                end
            ) as rn
        from active_cleaned
    ) t
    where rn = 1
    {% endif %}

),

transformed as (

    select
        sha2(portal_run_id::varchar, 256)           as workflow_run_hk,
        portal_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from merged

),

final as (

    select
        cast(workflow_run_hk    as char(64))       as workflow_run_hk,
        cast(portal_run_id      as char(16))       as portal_run_id,
        cast(load_datetime      as timestamptz)    as load_datetime,
        cast(record_source      as varchar(255))   as record_source,
        cast(last_seen_datetime as timestamptz)    as last_seen_datetime
    from transformed

)

select * from final
