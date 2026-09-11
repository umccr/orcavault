{#
    sat_s3object_fm uses the CDC datalake partition_0 || partition_1 || partition_2
    to compare which partitions are newer. Test here that the partition values are
    all valid, as this depends on the infra settings.
#}
select distinct partition_0, partition_1, partition_2
from {{ source('orcabus_filemanager', 's3_object') }}
where not (
    regexp_instr(partition_0, '^[0-9]{4}$') > 0 and
    regexp_instr(partition_1, '^[0-9]{2}$') > 0 and
    regexp_instr(partition_2, '^[0-9]{2}$') > 0
)
