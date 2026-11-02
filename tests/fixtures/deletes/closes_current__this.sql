select
    library_sequencing_run_hk,
    '2026-10-01 01:00'::timestamptz as load_datetime,
    sha2(
        sha2(coalesce(cast(library_sequencing_run_hk as varchar), ''), 256)
        || sha2('orcabus_sequence_run_manager'::varchar, 256)
        || sha2(coalesce(cast(effective_from as varchar), ''), 256)
    , 256)::char(64) as hash_diff,
    effective_from,
    '9999-12-31 00:00:00'::timestamptz as effective_to,
    1::smallint as is_current
from (
    select library_sequencing_run_hk::char(64) as library_sequencing_run_hk, '2026-10-01 00:00'::timestamptz as effective_from
    from (
        select 'hk_deleted'::varchar as library_sequencing_run_hk
        union all select 'hk_unchanged'
    ) current_rows
) t
