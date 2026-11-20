{{ config(severity='warn') }}

{#

    Every row of the accreditation sample list (seed accreditation__library_run) should appear in the
    accreditation_lims mart. Returns each seed row that matched nothing, e.g. a library or run missing from
    lims / external_lims, or an ID typo in the seed.

    Warn rather than error: a run can drop out of lims upstream (e.g. not SUCCEEDED), which should be
    investigated but not block the daily build.

#}

select
    acc.label,
    acc.library_id,
    acc.sequencing_run_id
from {{ ref('accreditation__library_run') }} acc
where not exists (
    select 1
    from {{ ref('accreditation_lims') }} mart
    where mart.label = acc.label
      and mart.library_id = acc.library_id
      and coalesce(mart.sequencing_run_id, '') = coalesce(acc.sequencing_run_id, '')
)
