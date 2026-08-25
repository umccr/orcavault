{{
    config(
        materialized='table',
        dist='portal_run_id',
        sort=['portal_run_id', 'bucket']
    )
}}

with location1 as (

    select
        sat.portal_run_id                                                   as portal_run_id,
        hub.bucket                                                          as bucket,
        min(regexp_substr(hub."key", '.*[0-9]{8}[a-zA-Z0-9]{8}/'))          as prefix,
        count(1)                                                            as key_count
    from
        {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_fm_current') }} cur on cur.s3object_hk = hub.s3object_hk
    where
        regexp_instr(hub."key", '(^v1|^byob-icav2/.*(analysis|primary))/.*[0-9]{8}[a-zA-Z0-9]{8}/') > 0
        {#      and regexp_instr(hub."key", '^byob-icav2/.*/logs/') = 0         #}
        {#      and regexp_instr(hub."key", '.*iap_xaccount_test\.tmp') = 0     #}
        and cur.is_current = 1
        and cur.is_deleted = 0
        and cur.version_active = 1
    group by
        sat.portal_run_id, hub.bucket

),

location2 as (

    select
        sat.portal_run_id                                                   as portal_run_id,
        hub.bucket                                                          as bucket,
        min(regexp_substr(hub."key", '.*[0-9]{8}[a-zA-Z0-9]{8}/'))          as prefix,
        count(1)                                                            as key_count
    from
        {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_portal') }} por on por.s3object_hk = hub.s3object_hk
    where
        hub.bucket not in ( select bucket from {{ ref('int_bucket_fm') }} )
    group by
        sat.portal_run_id, hub.bucket

),

merged as (

    select * from location1
    union
    select * from location2

),

transformed as (

    select
        portal_run_id,
        {{ extract_cohort_id('prefix') }}                                   as cohort_id,
        bucket,
        prefix,
        key_count
    from
        merged

),

final as (

    select
        cast(portal_run_id      as char(16))                                as portal_run_id,
        cast(cohort_id          as varchar(255))                            as cohort_id,
        cast(bucket             as varchar(63))                             as bucket,
        cast(prefix             as varchar(1024))                           as prefix,
        cast(key_count          as bigint)                                  as key_count
    from
        transformed
    order by
        portal_run_id desc nulls last

)

select * from final
