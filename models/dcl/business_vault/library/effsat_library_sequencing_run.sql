{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='library_sequencing_run_hk',
        on_schema_change='fail',
        dist='library_sequencing_run_hk',
        sort=['library_sequencing_run_hk', 'load_datetime']
    )
}}

{#

The effectivity of a library on a sequencing run. A library can be on many runs and a run has many libraries.

A link from the sequence run manager is effective while it has at least one association. A link can have more than
one, e.g. a library on two sequences with the same instrument run. It ends when its last association is deleted, i.e.
`sat_library_sequencing_run_srm` has a row with `op = 'D'`, and is effective again if an association is created
again. A link from another source is always effective, because those sources are snapshots that don't delete. So is
a link from the sequence run manager without any rows in the satellite, as there is nothing to end it.

Each run computes the whole history of the links that changed, and replaces their rows. It can't merge on `hash_diff`
like the other effectivity satellites, because a period can start at a different time when it's computed again, e.g.
when an earlier association arrives late, and merging would leave the period it replaces current.

#}

with incremental as (

    {# The links that are new, or have a new sequence run manager row. #}

    select library_sequencing_run_hk
    from {{ ref('link_library_sequencing_run') }}
    {% if is_incremental() %}
    where {{ load_bound('load_datetime') }}

    union

    select library_sequencing_run_hk
    from {{ ref('sat_library_sequencing_run_srm') }}
    where {{ load_bound('load_datetime') }}
    {% endif %}

),

links as (

    select
        lnk.library_sequencing_run_hk,
        lnk.load_datetime,
        lnk.record_source,
        lib.library_id,
        run.sequencing_run_id
    from {{ ref('link_library_sequencing_run') }} lnk
        inner join incremental i
            on i.library_sequencing_run_hk = lnk.library_sequencing_run_hk
        left join {{ ref('hub_library') }} lib
            on lib.library_hk = lnk.library_hk
        left join {{ ref('hub_sequencing_run') }} run
            on run.sequencing_run_hk = lnk.sequencing_run_hk

),

srm_associations as (

    {#
    Whether each association of a link is effective after each of its changes.
    #}

    select
        sat.library_sequencing_run_hk,
        sat.orcabus_id,
        sat._dms_cdc_timestamp                              as changed_at,
        min(case when sat.op = 'D' then 0 else 1 end)       as is_effective
    from {{ ref('sat_library_sequencing_run_srm') }} sat
        inner join links lnk
            on lnk.library_sequencing_run_hk = sat.library_sequencing_run_hk
    where lnk.record_source = 'orcabus_sequence_run_manager'
    group by sat.library_sequencing_run_hk, sat.orcabus_id, sat._dms_cdc_timestamp

),

srm_changes as (

    {#
    This counts the number of associations a link has. Changes at the same time are added together.
    #}

    select
        library_sequencing_run_hk,
        changed_at,
        sum(is_effective - coalesce(was_effective, 0))      as association_change
    from (
        select
            *,
            lag(is_effective) over (
                partition by library_sequencing_run_hk, orcabus_id
                order by changed_at
            )                                               as was_effective
        from srm_associations
    ) t
    group by library_sequencing_run_hk, changed_at

),

srm_effective as (

    {# A link is effective when it has at least one association. #}

    select
        library_sequencing_run_hk,
        changed_at,
        case
            when sum(association_change) over (
                partition by library_sequencing_run_hk
                order by changed_at
                rows between unbounded preceding and current row
            ) > 0 then 1
            else 0
        end                                                 as is_effective
    from srm_changes

),

srm_transitions as (

    {# The changes where a link becomes effective, or stops being effective. #}

    select * from (
        select
            *,
            lag(is_effective) over (
                partition by library_sequencing_run_hk
                order by changed_at
            )                                               as was_effective
        from srm_effective
    ) t
    where was_effective is null
       or was_effective <> is_effective

),

periods as (

    {# A link from the sequence run manager is effective from the start time until the next transition. #}

    select
        library_sequencing_run_hk,
        effective_from,
        effective_to
    from (
        select
            library_sequencing_run_hk,
            is_effective,
            changed_at                                      as effective_from,
            lead(changed_at) over (
                partition by library_sequencing_run_hk
                order by changed_at
            )                                               as effective_to
        from srm_transitions
    ) t
    where is_effective = 1

    union all

    {# Any other link is effective from when it was loaded. #}

    select
        lnk.library_sequencing_run_hk,
        lnk.load_datetime                                   as effective_from,
        cast(null as timestamptz)                           as effective_to
    from links lnk
        left join (select distinct library_sequencing_run_hk from srm_associations) srm
            on srm.library_sequencing_run_hk = lnk.library_sequencing_run_hk
    where srm.library_sequencing_run_hk is null

),

transformed as (

    select
        p.library_sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz)         as load_datetime,
        lnk.record_source,
        {{ generate_hash_diff([
            'p.library_sequencing_run_hk',
            'lnk.record_source',
            'p.effective_from'
        ]) }}                                               as hash_diff,
        lnk.library_id,
        lnk.sequencing_run_id,
        p.effective_from,
        coalesce(p.effective_to, cast('9999-12-31 00:00:00' as timestamptz))
                                                            as effective_to,
        case when p.effective_to is null then 1 else 0 end  as is_current
    from periods p
        inner join links lnk
            on lnk.library_sequencing_run_hk = p.library_sequencing_run_hk

),

final as (

    {# A period that was loaded before keeps its `load_datetime`, so only its end changes, which keeps the same behaviour as a merge. #}

    select
        cast(t.library_sequencing_run_hk    as char(64))        as library_sequencing_run_hk,
        {% if is_incremental() %}
        cast(coalesce(existing.load_datetime, t.load_datetime)
                                            as timestamptz)     as load_datetime,
        {% else %}
        cast(t.load_datetime                as timestamptz)     as load_datetime,
        {% endif %}
        cast(t.record_source                as varchar(100))    as record_source,
        cast(t.hash_diff                    as char(64))        as hash_diff,
        cast(t.library_id                   as varchar(255))    as library_id,
        cast(t.sequencing_run_id            as varchar(255))    as sequencing_run_id,
        cast(t.effective_from               as timestamptz)     as effective_from,
        cast(t.effective_to                 as timestamptz)     as effective_to,
        cast(t.is_current                   as smallint)        as is_current
    from transformed t
    {% if is_incremental() %}
        left join {{ this }} existing
            on existing.hash_diff = t.hash_diff
    {% endif %}

)

select * from final
