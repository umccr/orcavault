{{
    config(
        materialized='table',
        dist='sequencing_run_id',
        sort=['sequencing_run_id', 'portal_run_id', 'library_id']
    )
}}

with location1 as (

    select
        sat.sequencing_run_id                                               as sequencing_run_id,
        sat.portal_run_id                                                   as portal_run_id,
        hub.bucket                                                          as bucket,
        hub."key"                                                           as "key",
        {{ extract_library_id_primary('hub."key"') }}                       as library_id,
        sat.filename                                                        as filename,
        sat.ext1                                                            as format,
        cur."size"                                                          as "size",
        cur.storage_class                                                   as storage_class,
        cur.e_tag                                                           as e_tag,
        cur.last_modified_date                                              as last_modified_date
    from
        {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_fm_current') }} cur on cur.s3object_hk = hub.s3object_hk
    where
        (sat.ext1 = 'gz' or sat.ext1 = 'ora')
        and sat.ext2 = 'fastq'
        and cur.is_current = 1
        and cur.is_deleted = 0
        and cur.version_active = 1

),

location2 as (

    select
        sat.sequencing_run_id                                               as sequencing_run_id,
        sat.portal_run_id                                                   as portal_run_id,
        hub.bucket                                                          as bucket,
        hub."key"                                                           as "key",
        {{ extract_library_id_primary('hub."key"') }}                       as library_id,
        sat.filename                                                        as filename,
        sat.ext1                                                            as format,
        por."size"                                                          as "size",
        cast(null as varchar(255))                                          as storage_class,
        por.e_tag                                                           as e_tag,
        por.last_modified_date                                              as last_modified_date
    from
        {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_portal') }} por on por.s3object_hk = hub.s3object_hk
    where
        hub.bucket not in ( select bucket from {{ ref('int_bucket_fm') }} )
        and (sat.ext1 = 'gz' or sat.ext1 = 'ora')
        and sat.ext2 = 'fastq'

),

merged as (

    select * from location1
    union
    select * from location2

),

transformed as (

    select
        sequencing_run_id,
        {{ extract_sequencing_run_date('sequencing_run_id') }}              as sequencing_run_date,
        portal_run_id,
        {{ extract_cohort_id('"key"') }}                                    as cohort_id,
        bucket,
        "key",
        library_id,
        filename,
        format,
        "size",
        storage_class,
        e_tag,
        last_modified_date
    from
        merged

),

final as (

    select
        cast(sequencing_run_id  as varchar(255))                            as sequencing_run_id,
        cast(sequencing_run_date as date)                                   as sequencing_run_date,
        cast(portal_run_id      as char(16))                                as portal_run_id,
        cast(cohort_id          as varchar(255))                            as cohort_id,
        cast(bucket             as varchar(63))                             as bucket,
        cast("key"              as varchar(1024))                           as "key",
        cast(library_id         as varchar(255))                            as library_id,
        cast(filename           as varchar(1024))                           as filename,
        cast(format             as varchar(255))                            as format,
        cast("size"             as bigint)                                  as "size",
        cast(storage_class      as varchar(255))                            as storage_class,
        cast(e_tag              as varchar(255))                            as e_tag,
        cast(last_modified_date as timestamptz)                             as last_modified_date
    from
        transformed
    order by
        sequencing_run_date desc nulls last,
        library_id desc

)

select * from final
