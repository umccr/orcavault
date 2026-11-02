select sha2(sequencing_run_id, 256)::char(64) as sequencing_run_hk, sequencing_run_id
from (
    select 'RUN_A'::varchar as sequencing_run_id
    union all select 'RUN_OLD'
) runs
