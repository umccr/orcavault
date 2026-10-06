select 'old_seq'::varchar as orcabus_id, 'RUN_OLD'::varchar as instrument_run_id, '2026-10-04 12:00'::timestamp as _dms_cdc_timestamp
union all select 'new_seq',    'RUN_NEW',    '2026-10-05 00:30'
union all select 'future_seq', 'RUN_FUTURE', '2026-10-05 01:30'
