{{
    config(
        materialized='ephemeral'
    )
}}

{# Note: Using the `history_date` and `history_id` level details for tie breaker. #}

select * from (
    select
        lib.library_id                                  as library_id,
        lib.subject_orcabus_id                          as subject_orcabus_id,
        sbj.subject_id                                  as external_subject_id,
        greatest(
            cast(lib.history_date as timestamptz),
            cast(sbj.history_date as timestamptz),
            cast(lib._dms_cdc_timestamp as timestamptz),
            cast(sbj._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_metadata_manager'                      as record_source,
        row_number() over (
            partition by lib.library_id, lib.subject_orcabus_id
            order by
                greatest(
                    cast(lib.history_date as timestamptz),
                    cast(sbj.history_date as timestamptz),
                    cast(lib._dms_cdc_timestamp as timestamptz),
                    cast(sbj._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_mm_historicallibrary') }} lib
    join {{ ref('int_cdc_mm_historicalsubject') }} sbj
        on sbj.orcabus_id = lib.subject_orcabus_id
) t
where rn = 1
