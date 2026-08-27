{{
    config(
        materialized='ephemeral'
    )
}}

{# Note: Using the `history_date` and `history_id` level details for tie breaker. #}

select * from (
    select
        lib.library_id                                  as library_id,
        lib.sample_orcabus_id                           as sample_orcabus_id,
        smp.sample_id                                   as sample_id,
        smp.external_sample_id                          as external_sample_id,
        smp.source                                      as source,
        greatest(
            cast(lib.history_date as timestamptz),
            cast(smp.history_date as timestamptz),
            cast(lib._dms_cdc_timestamp as timestamptz),
            cast(smp._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_metadata_manager'                      as record_source,
        row_number() over (
            partition by lib.library_id, lib.sample_orcabus_id
            order by
                greatest(
                    cast(lib.history_date as timestamptz),
                    cast(smp.history_date as timestamptz),
                    cast(lib._dms_cdc_timestamp as timestamptz),
                    cast(smp._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_mm_historicallibrary') }} lib
    join {{ ref('int_cdc_mm_historicalsample') }} smp
        on smp.orcabus_id = lib.sample_orcabus_id
) t
where rn = 1
