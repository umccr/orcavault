{{
    config(
        materialized='ephemeral'
    )
}}

select
    subject_orcabus_id,
    individual_orcabus_id,
    max(load_datetime) as load_datetime
from {{ ref('cdc_mm_app_subjectindividuallink') }}
group by subject_orcabus_id, individual_orcabus_id
