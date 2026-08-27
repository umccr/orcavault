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
    from {{ source('orcabus_metadata_manager', 'app_project') }}
) t
where rn = 1
