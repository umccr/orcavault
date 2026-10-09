select 'lib_changed'::varchar as orcabus_id, '2026-10-04 12:00'::timestamp as _dms_cdc_timestamp
union all select 'lib_changed',     '2026-10-05 00:30'
union all select 'lib_unchanged',   '2026-10-04 12:00'
union all select 'lib_not_visible', '2026-10-04 12:00'
union all select 'lib_not_visible', '2026-10-05 01:30'
union all select 'lib_at_position', '2026-10-05 00:00'
union all select 'lib_at_pending',  '2026-10-05 01:00'
