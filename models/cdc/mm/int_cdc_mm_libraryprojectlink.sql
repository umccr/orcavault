{{
    config(
        materialized='ephemeral'
    )
}}

select
    library_orcabus_id,
    project_orcabus_id,
    max(load_datetime) as load_datetime
from {{ ref('cdc_mm_app_libraryprojectlink') }}
group by library_orcabus_id, project_orcabus_id
