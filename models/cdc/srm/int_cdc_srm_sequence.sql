{{
    config(
        materialized='ephemeral'
    )
}}

select * from (
    select
        *,
        row_number() over (
            partition by orcabus_id
            order by _dms_cdc_timestamp desc
        ) as rn
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
) t
where rn = 1
