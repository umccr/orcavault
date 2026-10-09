{#-

We expect the filemanager to have records coming in frequently, so assert it
here and warn if the warehouse hasn't seen something in a few days.

-#}

{{ config(severity='warn') }}

select
    source_id,
    pending,
    datediff(day, cast(pending as timestamp), getdate()) as days_behind
from ops.cdc_watermark
where source_id = 'orcabus_filemanager.s3_object'
  and pending < dateadd(day, -3, getdate())
