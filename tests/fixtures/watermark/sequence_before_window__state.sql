select
    orcabus_id, sequence_id, _dms_cdc_timestamp,
    'STARTED'::varchar as status, _dms_cdc_timestamp as "timestamp", null::varchar as comment, 'I'::varchar as op
from (
    select 'new_state_old_seq'::varchar as orcabus_id, 'old_seq'::varchar as sequence_id, '2026-10-05 00:30'::timestamp as _dms_cdc_timestamp
    union all select 'old_state_new_seq',    'new_seq',    '2026-10-04 12:00'
    union all select 'old_state_old_seq',    'old_seq',    '2026-10-04 12:00'
    union all select 'new_state_future_seq', 'future_seq', '2026-10-05 00:30'
) states
