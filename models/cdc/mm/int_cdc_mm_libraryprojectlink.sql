{{
    config(
        materialized='ephemeral'
    )
}}

select distinct
    library_orcabus_id,
    project_orcabus_id
from {{ source('orcabus_metadata_manager', 'app_libraryprojectlink') }}
