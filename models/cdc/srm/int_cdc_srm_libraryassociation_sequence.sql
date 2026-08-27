{{
    config(
        materialized='ephemeral'
    )
}}

select * from (
    select
        assoc.library_id                                as library_id,
        seq.instrument_run_id                           as sequencing_run_id,
        greatest(
            cast(assoc._dms_cdc_timestamp as timestamptz),
            cast(seq._dms_cdc_timestamp as timestamptz)
        )                                               as association_date,
        'orcabus_sequence_run_manager'                  as record_source,
        row_number() over (
            partition by assoc.library_id, seq.instrument_run_id
            order by
                greatest(
                    cast(assoc._dms_cdc_timestamp as timestamptz),
                    cast(seq._dms_cdc_timestamp as timestamptz)
                ) desc
        ) as rn
    from {{ ref('int_cdc_srm_libraryassociation') }} assoc
    join {{ ref('int_cdc_srm_sequence') }} seq
        on seq.orcabus_id = assoc.sequence_id
) t
where rn = 1
