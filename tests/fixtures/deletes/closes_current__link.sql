select
    library_sequencing_run_hk::char(64) as library_sequencing_run_hk,
    sha2('RUN_A', 256)::char(64) as sequencing_run_hk,
    sha2(library_id, 256)::char(64) as library_hk,
    load_datetime,
    'orcabus_sequence_run_manager'::varchar as record_source
from (
    select 'hk_deleted'::varchar as library_sequencing_run_hk, 'L_DELETED'::varchar as library_id,
        '2026-10-01 01:00'::timestamptz as load_datetime
    union all select 'hk_unchanged', 'L_UNCHANGED', '2026-10-01 01:00'
    union all select 'hk_new',       'L_NEW',       '2026-10-05 02:00'
) links
