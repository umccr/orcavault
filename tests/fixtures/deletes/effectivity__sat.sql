select
    library_sequencing_run_hk::char(64) as library_sequencing_run_hk, orcabus_id, op, _dms_cdc_timestamp,
    '2026-10-05 02:00'::timestamptz as load_datetime
from (
    select 'hk_live'::varchar as library_sequencing_run_hk, 'assoc_live'::varchar as orcabus_id, 'I'::varchar as op,
        '2026-10-01 00:00'::timestamptz as _dms_cdc_timestamp
    union all select 'hk_deleted',        'assoc_deleted', 'I', '2026-10-01 00:00'
    union all select 'hk_deleted',        'assoc_deleted', 'D', '2026-10-03 00:00'
    union all select 'hk_recreated',      'assoc_old',     'I', '2026-10-01 00:00'
    union all select 'hk_recreated',      'assoc_old',     'D', '2026-10-02 00:00'
    union all select 'hk_recreated',      'assoc_new',     'I', '2026-10-03 00:00'
    union all select 'hk_replaced',       'assoc_old',     'I', '2026-10-01 00:00'
    union all select 'hk_replaced',       'assoc_old',     'D', '2026-10-02 00:00'
    union all select 'hk_replaced',       'assoc_new',     'I', '2026-10-02 00:00'
    union all select 'hk_legacy_deleted', 'assoc_legacy',  'I', '2026-10-01 00:00'
    union all select 'hk_legacy_deleted', 'assoc_legacy',  'D', '2026-10-02 00:00'
) changes
