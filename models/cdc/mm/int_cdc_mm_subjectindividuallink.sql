{{
    config(
        materialized='ephemeral'
    )
}}

select distinct
    subject_orcabus_id,
    individual_orcabus_id
from {{ source('orcabus_metadata_manager', 'app_subjectindividuallink') }}
