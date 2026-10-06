select 'old_lib'::varchar as library_id, '2026-10-04 12:00'::timestamp as _dms_cdc_timestamp
union all select 'new_lib',    '2026-10-05 00:30'
union all select 'future_lib', '2026-10-05 01:30'
