{{
    config(
        materialized='ephemeral'
    )
}}

select
    subject_orcabus_id,
    individual_orcabus_id,
    {{ cdc_window('orcabus_metadata_manager', 'app_subjectindividuallink') }} as cdc_changed
from (
    select
        subject_orcabus_id,
        individual_orcabus_id,
        max(_dms_cdc_timestamp) as _dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_subjectindividuallink') }}
    where {{ cdc_upper_bound('orcabus_metadata_manager', 'app_subjectindividuallink') }}
    group by subject_orcabus_id, individual_orcabus_id
) links
