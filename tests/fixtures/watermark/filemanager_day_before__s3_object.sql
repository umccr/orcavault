select
    'bucket'::varchar as bucket, "key",
    '2026'::varchar as partition_0, '10'::varchar as partition_1, partition_2,
    '2026-10-05 00:30'::timestamp as _dms_cdc_timestamp
from (
    select 'today'::varchar as "key", '05'::varchar as partition_2
    union all select 'previous_day',  '04'
    union all select 'two_days_back', '03'
) objects
