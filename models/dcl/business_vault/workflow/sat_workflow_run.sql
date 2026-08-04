{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='workflow_run_hk',
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# ============================================================ #}

with cdc_affected_keys as (

    {% if is_incremental() %}

    select distinct workflow_run_hk
    from (
        select workflow_run_hk, _dms_cdc_timestamp from {{ ref('sat_workflow_run_detail') }}
        union all
        select workflow_run_hk, _dms_cdc_timestamp from {{ ref('sat_workflow_run_comment') }}
        union all
        select workflow_run_hk, _dms_cdc_timestamp from {{ ref('sat_workflow_run_state') }}
    ) t
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})

    {% else %}

    select distinct workflow_run_hk
    from (
        select workflow_run_hk from {{ ref('sat_workflow_run_detail') }}
        union all
        select workflow_run_hk from {{ ref('sat_workflow_run_comment') }}
        union all
        select workflow_run_hk from {{ ref('sat_workflow_run_state') }}
    ) t

    {% endif %}

),

cdc_detail_latest as (

    select
        d.workflow_run_hk,
        d.record_source,
        d.workflow_name,
        d.workflow_version,
        d.workflow_code_version,
        d.workflow_validation_state,
        case when d.op = 'D' then 1 else 0 end as is_deleted
    from {{ ref('sat_workflow_run_detail') }} d
    inner join cdc_affected_keys ak on ak.workflow_run_hk = d.workflow_run_hk
    qualify row_number() over (
        partition by d.workflow_run_hk
        order by d._dms_cdc_timestamp desc
    ) = 1

),

cdc_state_latest as (

    {# Note - We can also compute average workflow_run_start time instead. Due to variability of what define #}
    {# the start condition. Do we consider the queuing time? A bit of Veracity and Variety with status enum. #}
    {# e.g. AVG/MAX/MIN(state_timestamp) among any of comparing ('READY', 'QUEUED', '..', 'RUNNING') states. #}
    {# This is the business question and, hence in Business Vault. And tune according to the requirements.   #}

    select
        s.workflow_run_hk,
        min(case when s.status in ('READY', 'INITIALIZING', 'QUEUED', 'PREPARING_INPUTS', 'RUNNING')
            then s.state_timestamp end)                         as workflow_run_start,
        max(case when s.status in ('SUCCEEDED', 'FAILED', 'ABORTED')
            then s.state_timestamp end)                         as workflow_run_end,
        max(case when rn = 1 then s.status end)                 as workflow_run_status,
        max(case when rn = 1 then s.comment end)                as state_comment
    from (
        select
            *,
            row_number() over (
                partition by workflow_run_hk
                order by _dms_cdc_timestamp desc, state_timestamp desc
            ) as rn
        from {{ ref('sat_workflow_run_state') }}
        where workflow_run_hk in (select workflow_run_hk from cdc_affected_keys)
    ) s
    group by s.workflow_run_hk

),

cdc_comment_latest as (

    select
        c.workflow_run_hk,
        c.comment
    from {{ ref('sat_workflow_run_comment') }} c
    inner join cdc_affected_keys ak on ak.workflow_run_hk = c.workflow_run_hk
    qualify row_number() over (
        partition by c.workflow_run_hk
        order by c._dms_cdc_timestamp desc
    ) = 1

),

cdc_derived as (

    select
        d.workflow_run_hk,
        d.record_source,
        d.workflow_name,
        d.workflow_version,
        d.workflow_code_version,
        d.workflow_validation_state,
        s.workflow_run_status,
        s.workflow_run_start,
        s.workflow_run_end,
        coalesce(s.state_comment, c.comment)    as workflow_run_comment,
        d.is_deleted
    from cdc_detail_latest d
        left join cdc_state_latest s    on s.workflow_run_hk = d.workflow_run_hk
        left join cdc_comment_latest c  on c.workflow_run_hk = d.workflow_run_hk

),

{% if var('load_legacy', false) %}

legacy_derived as (

    select
        workflow_run_hk,
        record_source,
        type_name                                   as workflow_name,
        version                                     as workflow_version,
        null                                        as workflow_code_version,
        null                                        as workflow_validation_state,
        split_part(end_status, ';;', 1)             as workflow_run_status,
        start_datetime                              as workflow_run_start,
        end_datetime                                as workflow_run_end,
        nullif(split_part(end_status, ';;', 2), '') as workflow_run_comment,
        0                                           as is_deleted
    from {{ ref('sat_workflow_run_portal_legacy') }}

),

{% endif %}

aliased as (

    {% if is_incremental() %}

    select
        sal.alias_workflow_run_hk   as workflow_run_hk,
        sal.record_source,
        sat.workflow_name,
        sat.workflow_version,
        sat.workflow_code_version,
        sat.workflow_validation_state,
        sat.workflow_run_status,
        sat.workflow_run_start,
        sat.workflow_run_end,
        sat.workflow_run_comment,
        sat.is_deleted
    from {{ this }} sat
        join {{ ref('sal_workflow_run') }} sal
            on sal.base_workflow_run_hk = sat.workflow_run_hk
    where not exists (
        select 1 from {{ this }} t
        where t.workflow_run_hk = sal.alias_workflow_run_hk
    )

    {% else %}

    select
        sal.alias_workflow_run_hk   as workflow_run_hk,
        sal.record_source,
        sat.workflow_name,
        sat.workflow_version,
        sat.workflow_code_version,
        sat.workflow_validation_state,
        sat.workflow_run_status,
        sat.workflow_run_start,
        sat.workflow_run_end,
        sat.workflow_run_comment,
        sat.is_deleted
    from cdc_derived sat
        join {{ ref('sal_workflow_run') }} sal
            on sal.base_workflow_run_hk = sat.workflow_run_hk

    {% endif %}

),

merged as (

    select * from cdc_derived

    {% if var('load_legacy', false) %}
    union all
    select * from legacy_derived
    {% endif %}

    union all
    select * from aliased

),

transformed as (

    select
        workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'workflow_name',
            'workflow_version',
            'workflow_code_version',
            'workflow_validation_state',
            'is_deleted',
            'workflow_run_status',
            'workflow_run_start',
            'workflow_run_end'
        ]) }}                                       as hash_diff,
        workflow_name,
        workflow_version,
        workflow_code_version,
        workflow_validation_state,
        workflow_run_status,
        workflow_run_start,
        workflow_run_end,
        workflow_run_comment,
        is_deleted
    from merged

),

final as (

    select
        cast(workflow_run_hk            as char(64))        as workflow_run_hk,
        cast(load_datetime              as timestamptz)     as load_datetime,
        cast(record_source              as varchar(100))    as record_source,
        cast(hash_diff                  as char(64))        as hash_diff,
        cast(workflow_name              as varchar(255))    as workflow_name,
        cast(workflow_version           as varchar(100))    as workflow_version,
        cast(workflow_code_version      as varchar(100))    as workflow_code_version,
        cast(workflow_validation_state  as varchar(100))    as workflow_validation_state,
        cast(workflow_run_status        as varchar(255))    as workflow_run_status,
        cast(workflow_run_start         as timestamptz)     as workflow_run_start,
        cast(workflow_run_end           as timestamptz)     as workflow_run_end,
        cast(workflow_run_comment       as varchar(65535))  as workflow_run_comment,
        cast(is_deleted                 as smallint)        as is_deleted
    from transformed

)

select * from final
