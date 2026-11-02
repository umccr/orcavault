select
    'assoc_deleted'::varchar as orcabus_id, 'L_DELETED'::varchar as library_id, 'seq_a'::varchar as sequence_id,
    '2026-10-01 00:00'::timestamp as association_date, 'ACTIVE'::varchar as status, 'I'::varchar as op,
    '2026-10-04 12:00'::timestamp as _dms_cdc_timestamp
union all select 'assoc_deleted',   null,     null,    null,               null,     'D', '2026-10-05 00:30'
union all select 'assoc_kept',      'L_KEPT', 'seq_a', '2026-10-01 00:00', 'ACTIVE', 'I', '2026-10-04 12:00'
union all select 'assoc_same_time', null,     null,    null,               null,     'D', '2026-10-05 00:30'
union all select 'assoc_same_time', 'L_SAME', 'seq_a', '2026-10-05 00:30', 'ACTIVE', 'I', '2026-10-05 00:30'
