select sha2(library_id, 256)::char(64) as library_hk, library_id
from (
    select 'L_LIVE'::varchar as library_id
    union all select 'L_DELETED'
    union all select 'L_RECREATED'
    union all select 'L_REPLACED'
    union all select 'L_LEGACY'
    union all select 'L_LEGACY_DELETED'
    union all select 'L_NEW'
    union all select 'L_UNCHANGED'
) libraries
