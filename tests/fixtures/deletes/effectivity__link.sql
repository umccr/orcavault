select
    library_sequencing_run_hk::char(64) as library_sequencing_run_hk,
    sha2(sequencing_run_id, 256)::char(64) as sequencing_run_hk,
    sha2(library_id, 256)::char(64) as library_hk,
    load_datetime,
    record_source
from (
    select 'hk_live'::varchar as library_sequencing_run_hk, 'L_LIVE'::varchar as library_id, 'RUN_A'::varchar as sequencing_run_id,
        '2026-10-01 01:00'::timestamptz as load_datetime, 'orcabus_sequence_run_manager'::varchar as record_source
    union all select 'hk_deleted',        'L_DELETED',        'RUN_A',   '2026-10-01 01:00', 'orcabus_sequence_run_manager'
    union all select 'hk_recreated',      'L_RECREATED',      'RUN_A',   '2026-10-01 01:00', 'orcabus_sequence_run_manager'
    union all select 'hk_replaced',       'L_REPLACED',       'RUN_A',   '2026-10-01 01:00', 'orcabus_sequence_run_manager'
    union all select 'hk_legacy',         'L_LEGACY',         'RUN_OLD', '2026-09-01 00:00', 'legacy_data_portal_libraryrun'
    union all select 'hk_legacy_deleted', 'L_LEGACY_DELETED', 'RUN_A',   '2026-09-01 00:00', 'spreadsheet__google_lims'
) links
