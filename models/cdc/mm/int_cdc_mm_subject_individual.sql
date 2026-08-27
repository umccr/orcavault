{{
    config(
        materialized='ephemeral'
    )
}}

select * from (
    select
        idv.individual_id                               as internal_subject_id,
        sbj.subject_id                                  as external_subject_id,
        greatest(
            cast(sbj._dms_cdc_timestamp as timestamptz),
            cast(idv._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_metadata_manager'                      as record_source,
        row_number() over (
            partition by idv.individual_id, sbj.subject_id
            order by
                greatest(
                    cast(sbj._dms_cdc_timestamp as timestamptz),
                    cast(idv._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_mm_subjectindividuallink') }} lnk
    join {{ ref('int_cdc_mm_subject') }} sbj
        on sbj.orcabus_id = lnk.subject_orcabus_id
    join {{ ref('int_cdc_mm_individual') }} idv
        on idv.orcabus_id = lnk.individual_orcabus_id
) t
where rn = 1
