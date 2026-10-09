{#

    hub_s3object, sat_s3object_fm and the `pending` in update_source_pending read the
    CDC datalake partition_0 || partition_1 || partition_2 as a YYYYMMDD commit date,
    to skip reading partitions unnecessarily. Test here that the partition values are
    all valid, as this depends on the infra settings.

#}
select distinct partition_0, partition_1, partition_2
from {{ source('orcabus_filemanager', 's3_object') }}
where not (
    regexp_instr(partition_0, '^[0-9]{4}$') > 0 and
    regexp_instr(partition_1, '^[0-9]{2}$') > 0 and
    regexp_instr(partition_2, '^[0-9]{2}$') > 0
)
