{{
    config(
        materialized='ephemeral'
    )
}}

select
    library_orcabus_id,
    project_orcabus_id,
    {{ cdc_window('orcabus_metadata_manager', 'app_libraryprojectlink') }} as cdc_changed
from (
    select
        library_orcabus_id,
        project_orcabus_id,
        max(_dms_cdc_timestamp) as _dms_cdc_timestamp
    from {{ source('orcabus_metadata_manager', 'app_libraryprojectlink') }}
    where {{ cdc_upper_bound('orcabus_metadata_manager', 'app_libraryprojectlink') }}
    group by library_orcabus_id, project_orcabus_id
) links
