{{
    config(
        materialized='incremental'
    )
}}

with source as (

    select * from {{ source('tsa', 'spreadsheet__library_tracking_metadata') }}

),

cleaned as (

    select
        trim(regexp_replace(assay,                 '[\n\r]+', '')) as assay,
        trim(regexp_replace(comments,              '[\n\r]+', '')) as comments,
        trim(regexp_replace(coverage,              '[\n\r]+', '')) as coverage,
        trim(regexp_replace(experiment_id,         '[\n\r]+', '')) as experiment_id,
        trim(regexp_replace(external_sample_id,    '[\n\r]+', '')) as external_sample_id,
        trim(regexp_replace(external_subject_id,   '[\n\r]+', '')) as external_subject_id,
        trim(regexp_replace(library_id,            '[\n\r]+', '')) as library_id,
        trim(regexp_replace(override_cycles,       '[\n\r]+', '')) as override_cycles,
        trim(regexp_replace(phenotype,             '[\n\r]+', '')) as phenotype,
        trim(regexp_replace(project_name,          '[\n\r]+', '')) as project_name,
        trim(regexp_replace(project_owner,         '[\n\r]+', '')) as project_owner,
        trim(regexp_replace(qpcr_id,               '[\n\r]+', '')) as qpcr_id,
        trim(regexp_replace(quality,               '[\n\r]+', '')) as quality,
        trim(regexp_replace(run,                   '[\n\r]+', '')) as run,
        trim(regexp_replace(sample_id,             '[\n\r]+', '')) as sample_id,
        trim(regexp_replace(sample_name,           '[\n\r]+', '')) as sample_name,
        trim(regexp_replace(samplesheet_sample_id, '[\n\r]+', '')) as samplesheet_sample_id,
        trim(regexp_replace(source,                '[\n\r]+', '')) as source,
        trim(regexp_replace(subject_id,            '[\n\r]+', '')) as subject_id,
        trim(regexp_replace(truseq_index,          '[\n\r]+', '')) as truseq_index,
        trim(regexp_replace(type,                  '[\n\r]+', '')) as type,
        trim(regexp_replace(workflow,              '[\n\r]+', '')) as workflow,
        trim(regexp_replace(r_rna,                 '[\n\r]+', '')) as r_rna,
        trim(regexp_replace(study,                 '[\n\r]+', '')) as study,
        trim(regexp_replace(sheet_name,            '[\n\r]+', '')) as sheet_name
    from
        source
    where
        coalesce
        (
            nullif(assay, ''),
            nullif(comments, ''),
            nullif(coverage, ''),
            nullif(experiment_id, ''),
            nullif(external_sample_id, ''),
            nullif(external_subject_id, ''),
            nullif(library_id, ''),
            nullif(override_cycles, ''),
            nullif(phenotype, ''),
            nullif(project_name, ''),
            nullif(project_owner, ''),
            nullif(qpcr_id, ''),
            nullif(quality, ''),
            nullif(run, ''),
            nullif(sample_id, ''),
            nullif(sample_name, ''),
            nullif(samplesheet_sample_id, ''),
            nullif(source, ''),
            nullif(subject_id, ''),
            nullif(truseq_index, ''),
            nullif(type, ''),
            nullif(workflow, ''),
            nullif(r_rna, ''),
            nullif(study, '')
        ) is not null

),

differentiated as (

    select
        *
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        assay,
        comments,
        coverage,
        experiment_id,
        external_sample_id,
        external_subject_id,
        library_id,
        override_cycles,
        phenotype,
        project_name,
        project_owner,
        qpcr_id,
        quality,
        run,
        sample_id,
        sample_name,
        samplesheet_sample_id,
        source,
        subject_id,
        truseq_index,
        type,
        workflow,
        r_rna,
        study,
        sheet_name
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        *,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'UMCCR_Library_Tracking_MetaData' as record_source
    from
        differentiated

),

final as (

    select * from transformed

)

select * from final
