{{
    config(
        materialized='ephemeral'
    )
}}

{# Note: Using the `history_date` and `history_id` level details for tie breaker. #}

select * from (
    select
        *,
        row_number() over (
            partition by orcabus_id
            order by _dms_cdc_timestamp desc, history_date desc, history_id desc
        ) as rn
    from {{ source('orcabus_metadata_manager', 'app_historicalsubject') }}
) t
where rn = 1
