{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['effective_to', 'is_current'],
        on_schema_change='fail',
        dist='library_sequencing_run_hk',
        sort=['library_sequencing_run_hk', 'load_datetime']
    )
}}

{#

The effectivity of a library on a sequencing run. A library can be on many runs and a run has many libraries.

A link from the sequence run manager is effective while there is an association. It ends when the
association is deleted, i.e. `sat_library_sequencing_run_srm` with a row with `op = 'D'`, and is effective
again if the associated is recreated. A link from another source is always effective, because those
sources are snapshots that don't delete.

#}

with incremental as (

    {# The links that are new, or have a new sequence run manager row,. #}

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

srm_changes as (

    {# Determines if the association of a link is created or deleted. #}

    select
        sat.library_sequencing_run_hk,
        sat._dms_cdc_timestamp                              as changed_at,
        max(case when sat.op = 'D' then 0 else 1 end)       as is_effective
    from {{ ref('sat_library_sequencing_run_srm') }} sat
        inner join links lnk
            on lnk.library_sequencing_run_hk = sat.library_sequencing_run_hk
    where lnk.record_source = 'orcabus_sequence_run_manager'
    group by sat.library_sequencing_run_hk, sat._dms_cdc_timestamp

),

srm_transitions as (

    {# Determines the changes for where a link becomes effective. #}

    select * from (
        select
            *,
            lag(is_effective) over (
                partition by library_sequencing_run_hk
                order by changed_at
            )                                               as was_effective
        from srm_changes
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

    select
        library_sequencing_run_hk,
        load_datetime                                       as effective_from,
        cast(null as timestamptz)                           as effective_to
    from links
    where record_source <> 'orcabus_sequence_run_manager'

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

    select
        cast(library_sequencing_run_hk  as char(64))        as library_sequencing_run_hk,
        cast(load_datetime              as timestamptz)     as load_datetime,
        cast(record_source              as varchar(100))    as record_source,
        cast(hash_diff                  as char(64))        as hash_diff,
        cast(library_id                 as varchar(255))    as library_id,
        cast(sequencing_run_id          as varchar(255))    as sequencing_run_id,
        cast(effective_from             as timestamptz)     as effective_from,
        cast(effective_to               as timestamptz)     as effective_to,
        cast(is_current                 as smallint)        as is_current
    from transformed

)

select * from final
