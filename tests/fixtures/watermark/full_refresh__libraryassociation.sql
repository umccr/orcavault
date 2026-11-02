select 'srm_lib'::varchar as library_id, 'I'::varchar as op, '2026-10-04 12:00'::timestamp as _dms_cdc_timestamp
union all select null,             'D', '2026-10-05 00:30'
union all select 'old_lib',        'I', '2026-10-04 12:00'
union all select 'future_srm_lib', 'I', '2026-10-05 01:30'
