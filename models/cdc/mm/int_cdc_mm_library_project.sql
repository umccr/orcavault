{{
    config(
        materialized='ephemeral'
    )
}}

select * from (
    select
        lib.library_id                                  as library_id,
        lib.orcabus_id                                  as library_orcabus_id,
        prj.project_id                                  as project_id,
        greatest(
            cast(lib._dms_cdc_timestamp as timestamptz),
            cast(prj._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_metadata_manager'                      as record_source,
        row_number() over (
            partition by lib.library_id, prj.project_id
            order by
                greatest(
                    cast(lib._dms_cdc_timestamp as timestamptz),
                    cast(prj._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_mm_library') }} lib
    join {{ ref('int_cdc_mm_libraryprojectlink') }} lnk
        on lnk.library_orcabus_id = lib.orcabus_id
    join {{ ref('int_cdc_mm_project') }} prj
        on prj.orcabus_id = lnk.project_orcabus_id
) t
where rn = 1
