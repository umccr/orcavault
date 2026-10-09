{#-

The `ops.cdc_watermark.position` and `ops.cdc_watermark.pending` should never be in the future.

-#}

select
    source_id,
    position,
    pending
from ops.cdc_watermark
where position > getdate()
   or pending > getdate()
