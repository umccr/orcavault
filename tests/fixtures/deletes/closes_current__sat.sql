select
    library_sequencing_run_hk::char(64) as library_sequencing_run_hk, op, _dms_cdc_timestamp, load_datetime
from (
    select 'hk_deleted'::varchar as library_sequencing_run_hk, 'I'::varchar as op,
        '2026-10-01 00:00'::timestamptz as _dms_cdc_timestamp, '2026-10-01 01:00'::timestamptz as load_datetime
    union all select 'hk_deleted',   'D', '2026-10-05 00:30', '2026-10-05 02:00'
    union all select 'hk_unchanged', 'I', '2026-10-01 00:00', '2026-10-01 01:00'
    union all select 'hk_new',       'I', '2026-10-05 00:30', '2026-10-05 02:00'
) changes
