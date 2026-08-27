{{
    config(
        materialized='ephemeral'
    )
}}

select * from (
    select
        wfr.portal_run_id                               as portal_run_id,
        lib.library_id                                  as library_id,
        greatest(
            cast(lnk._dms_cdc_timestamp as timestamptz),
            cast(wfr._dms_cdc_timestamp as timestamptz),
            cast(lib._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_workflow_manager'                      as record_source,
        row_number() over (
            partition by wfr.portal_run_id, lib.library_id
            order by
                greatest(
                    cast(lnk._dms_cdc_timestamp as timestamptz),
                    cast(wfr._dms_cdc_timestamp as timestamptz),
                    cast(lib._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_wfm_libraryassociation') }} lnk
    join {{ ref('int_cdc_wfm_workflowrun') }} wfr
        on wfr.orcabus_id = lnk.workflow_run_id
    join {{ ref('int_cdc_wfm_library') }} lib
        on lib.orcabus_id = lnk.library_id
) t
where rn = 1
