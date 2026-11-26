{{
    config(
        on_schema_change='fail',
        dist='library_id',
        sort=['label', 'library_id', 'sequencing_run_id']
    )
}}

{#

    Listing of the WGS accreditation libraries, with their accreditation label, in the same flat layout as `lims`.

    The sample list lives in the seed `accreditation__library_run`, sourced from the manifests at
    https://github.com/umccr/research-projects/tree/main/grimmond-lab/wgs-accreditation/data
        clin-list-manifest.csv
        control-list-germline-manifest.csv
        control-list-somatic-manifest.csv
        ptc-list-manifest.csv

    Centre libraries (seed rows with a sequencing_run_id) match `lims` on (library_id, sequencing_run_id).
    External libraries (seed rows without one) match `external_lims` on library_id.

    A seed row that matches nothing is reported by tests/assert_accreditation_library_run_matched.sql.

#}

with accreditation as (

    select
        label,
        library_id,
        nullif(sequencing_run_id, '') as sequencing_run_id
    from {{ ref('accreditation__library_run') }}

),

centre_library as (

    select
        acc.label,
        lims.sequencing_run_id,
        lims.sequencing_run_date,
        lims.library_id,
        lims.alias_library_id,
        lims.internal_subject_id,
        lims.external_subject_id,
        lims.sample_id,
        lims.external_sample_id,
        lims.experiment_id,
        lims.project_id,
        lims.owner_id,
        lims.workflow,
        lims.phenotype,
        lims.type,
        lims.assay,
        lims.quality,
        lims.source,
        lims.truseq_index,
        lims.load_datetime
    from accreditation acc
        join {{ ref('lims') }} lims
            on lims.library_id = acc.library_id
            and lims.sequencing_run_id = acc.sequencing_run_id

),

external_library as (

    select
        acc.label,
        ext.sequencing_run_id,
        ext.sequencing_run_date,
        ext.library_id,
        ext.alias_library_id,
        ext.internal_subject_id,
        ext.external_subject_id,
        ext.sample_id,
        ext.external_sample_id,
        ext.experiment_id,
        ext.project_id,
        ext.owner_id,
        ext.workflow,
        ext.phenotype,
        ext.type,
        ext.assay,
        ext.quality,
        ext.source,
        ext.truseq_index,
        ext.load_datetime
    from accreditation acc
        join {{ ref('external_lims') }} ext
            on ext.library_id = acc.library_id
    where acc.sequencing_run_id is null

),

transformed as (

    select * from centre_library
        union all
    select * from external_library

),

final as (

    select
        cast(label                  as varchar(255))    as label,
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
    from transformed

)

select * from final
