{{
    config(
        materialized='table',
        dist='bucket',
        sort=['bucket']
    )
}}

{# See doc string at models/dcl/business_vault/s3object/_int.yml #}

select distinct
    cast(bucket as varchar(63)) as bucket
from
    {{ ref('hub_s3object') }}
where
    record_source = 'orcabus_filemanager_s3_object'
