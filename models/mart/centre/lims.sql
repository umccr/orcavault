{{
    config(
        on_schema_change='fail',
        dist='sequencing_run_id',
        sort=['sequencing_run_id', 'library_id', 'sequencing_run_date']
    )
}}

with effective_sequencing_run as (

    {# FIXME this only solves recent Runs. implement proper effectivity satellite that consider all upstream sources #}

    select distinct
        hub.sequencing_run_hk,
        hub.sequencing_run_id,
        sat.status
    from {{ ref('hub_sequencing_run') }} hub
        left join {{ ref('sat_sequencing_run_detail') }} sat
            on hub.sequencing_run_hk = sat.sequencing_run_hk
    where sat.status = 'SUCCEEDED'
       or sat.status is null

),

effsat_library_ownership as (

    select lnk.*
    from {{ ref('link_library_ownership') }} lnk
        join {{ ref('effsat_library_ownership') }} effsat
            on effsat.library_owner_hk = lnk.library_owner_hk
    where effsat.is_current = 1

),

effsat_library_project as (

    select lnk.*
    from {{ ref('link_library_project') }} lnk
        join {{ ref('effsat_library_project') }} effsat
            on effsat.library_project_hk = lnk.library_project_hk
    where effsat.is_current = 1

),

effsat_library_sample as (

    select lnk.*
    from {{ ref('link_library_sample') }} lnk
        join {{ ref('effsat_library_sample') }} effsat
            on effsat.library_sample_hk = lnk.library_sample_hk
    where effsat.is_current = 1

),

effsat_library_external_sample as (

    select lnk.*
    from {{ ref('link_library_external_sample') }} lnk
        join {{ ref('effsat_library_external_sample') }} effsat
            on effsat.library_external_sample_hk = lnk.library_external_sample_hk
    where effsat.is_current = 1

),

effsat_library_external_subject as (

    select lnk.*
    from {{ ref('link_library_external_subject') }} lnk
        join {{ ref('effsat_library_external_subject') }} effsat
            on effsat.library_external_subject_hk = lnk.library_external_subject_hk
    where effsat.is_current = 1

),

effsat_library_internal_subject as (

    select lnk.*
    from {{ ref('link_library_internal_subject') }} lnk
        join {{ ref('effsat_library_internal_subject') }} effsat
            on effsat.library_internal_subject_hk = lnk.library_internal_subject_hk
    where effsat.is_current = 1

),

effsat_library_experiment as (

    select lnk.*
    from {{ ref('link_library_experiment') }} lnk
        join {{ ref('effsat_library_experiment') }} effsat
            on effsat.library_experiment_hk = lnk.library_experiment_hk
    where effsat.is_current = 1

),

effective_sat_library as (

    select
        *,
        row_number() over (
            partition by library_hk
            order by load_datetime desc
        ) as rank
    from {{ ref('sat_library_glab') }}

),

transformed as (

    select
        sqr.sequencing_run_id                                       as sequencing_run_id,
        {{ extract_sequencing_run_date("sqr.sequencing_run_id") }}  as sequencing_run_date,
        lib.library_id                                              as original_library_id,
        int_sbj.internal_subject_id                                 as internal_subject_id,
        ext_sbj.external_subject_id                                 as external_subject_id,
        smp.sample_id                                               as sample_id,
        ext_smp.external_sample_id                                  as external_sample_id,
        expr.experiment_id                                          as experiment_id,
        prj.project_id                                              as project_id,
        owner.owner_id                                              as owner_id,
        sat.workflow                                                as workflow,
        sat.phenotype                                               as phenotype,
        sat.type                                                    as type,
        sat.assay                                                   as assay,
        sat.quality                                                 as quality,
        sat.source                                                  as source,
        sat.truseq_index                                            as truseq_index,
        sat.load_datetime                                           as load_datetime
    from {{ ref('hub_library') }} lib
        left join {{ ref('link_library_sequencing_run') }} lnk1
            on lib.library_hk = lnk1.library_hk
        left join effective_sequencing_run sqr
            on lnk1.sequencing_run_hk = sqr.sequencing_run_hk
        left join effsat_library_internal_subject lnk2
            on lib.library_hk = lnk2.library_hk
        left join {{ ref('hub_internal_subject') }} int_sbj
            on lnk2.internal_subject_hk = int_sbj.internal_subject_hk
        left join effsat_library_external_subject lnk3
            on lib.library_hk = lnk3.library_hk
        left join {{ ref('hub_external_subject') }} ext_sbj
            on lnk3.external_subject_hk = ext_sbj.external_subject_hk
        left join effsat_library_sample lnk4
            on lib.library_hk = lnk4.library_hk
        left join {{ ref('hub_sample') }} smp
            on lnk4.sample_hk = smp.sample_hk
        left join effsat_library_external_sample lnk5
            on lib.library_hk = lnk5.library_hk
        left join {{ ref('hub_external_sample') }} ext_smp
            on lnk5.external_sample_hk = ext_smp.external_sample_hk
        left join effsat_library_experiment lnk6
            on lib.library_hk = lnk6.library_hk
        left join {{ ref('hub_experiment') }} expr
            on lnk6.experiment_hk = expr.experiment_hk
        left join effsat_library_project lnk7
            on lib.library_hk = lnk7.library_hk
        left join {{ ref('hub_project') }} prj
            on lnk7.project_hk = prj.project_hk
        left join effsat_library_ownership lnk8
            on lib.library_hk = lnk8.library_hk
        left join {{ ref('hub_owner') }} owner
            on lnk8.owner_hk = owner.owner_hk
        left join effective_sat_library sat
            on lib.library_hk = sat.library_hk
            and sat.rank = 1

),

applied_library_alias as (

    select
        {{ extract_library_id("t.original_library_id") }}  as library_id,
        sal.alias_library_id                                as alias_library_id,
        sal.base_library_id                                 as base_library_id,
        t.*
    from transformed t
        full join {{ ref('sal_library') }} sal
            on sal.alias_library_id = t.original_library_id

),

ranked_libraryrun as (

    select
        row_number() over (
            partition by library_id, sequencing_run_id
            order by length(alias_library_id) desc nulls last
        )                                                   as rank,
        *
    from applied_library_alias

),

final as (

    select
        cast(sequencing_run_id      as varchar(255))    as sequencing_run_id,
        cast(sequencing_run_date    as date)            as sequencing_run_date,
        cast(library_id             as varchar(255))    as library_id,
        cast(alias_library_id       as varchar(255))    as alias_library_id,
        cast(internal_subject_id    as varchar(255))    as internal_subject_id,
        cast(external_subject_id    as varchar(255))    as external_subject_id,
        cast(sample_id              as varchar(255))    as sample_id,
        cast(external_sample_id     as varchar(255))    as external_sample_id,
        cast(experiment_id          as varchar(255))    as experiment_id,
        cast(project_id             as varchar(255))    as project_id,
        cast(owner_id               as varchar(255))    as owner_id,
        cast(workflow               as varchar(255))    as workflow,
        cast(phenotype              as varchar(255))    as phenotype,
        cast(type                   as varchar(255))    as type,
        cast(assay                  as varchar(255))    as assay,
        cast(quality                as varchar(255))    as quality,
        cast(source                 as varchar(255))    as source,
        cast(truseq_index           as varchar(255))    as truseq_index,
        cast(load_datetime          as timestamptz)     as load_datetime
    from ranked_libraryrun
    where rank = 1
      and sequencing_run_id is not null
    order by sequencing_run_date desc nulls last, library_id desc

)

select * from final
