{{
    config(
        materialized='incremental'
    )
}}

with source as (

    select
        *
    from
        {{ source('tsa', 'spreadsheet__google_lims') }}

    {% if is_incremental() %}

    where cast("timestamp" as timestamptz) + interval '11 hours' > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )

    {% endif %}

),

cleaned as (

    select
        trim(regexp_replace(illumina_id,         '[\n\r]+', '')) as illumina_id,
        trim(regexp_replace(run,                 '[\n\r]+', '')) as run,
        trim(regexp_replace("timestamp",         '[\n\r]+', '')) as "timestamp",
        trim(regexp_replace(subject_id,          '[\n\r]+', '')) as subject_id,
        trim(regexp_replace(sample_id,           '[\n\r]+', '')) as sample_id,
        trim(regexp_replace(library_id,          '[\n\r]+', '')) as library_id,
        trim(regexp_replace(external_subject_id, '[\n\r]+', '')) as external_subject_id,
        trim(regexp_replace(external_sample_id,  '[\n\r]+', '')) as external_sample_id,
        trim(regexp_replace(external_library_id, '[\n\r]+', '')) as external_library_id,
        trim(regexp_replace(sample_name,         '[\n\r]+', '')) as sample_name,
        trim(regexp_replace(project_owner,       '[\n\r]+', '')) as project_owner,
        trim(regexp_replace(project_name,        '[\n\r]+', '')) as project_name,
        trim(regexp_replace(project_custodian,   '[\n\r]+', '')) as project_custodian,
        trim(regexp_replace(type,                '[\n\r]+', '')) as type,
        trim(regexp_replace(assay,               '[\n\r]+', '')) as assay,
        trim(regexp_replace(override_cycles,     '[\n\r]+', '')) as override_cycles,
        trim(regexp_replace(phenotype,           '[\n\r]+', '')) as phenotype,
        trim(regexp_replace(source,              '[\n\r]+', '')) as source,
        trim(regexp_replace(quality,             '[\n\r]+', '')) as quality,
        trim(regexp_replace(topup,               '[\n\r]+', '')) as topup,
        trim(regexp_replace(secondary_analysis,  '[\n\r]+', '')) as secondary_analysis,
        trim(regexp_replace(workflow,            '[\n\r]+', '')) as workflow,
        trim(regexp_replace(tags,                '[\n\r]+', '')) as tags,
        trim(regexp_replace(fastq,               '[\n\r]+', '')) as fastq,
        trim(regexp_replace(number_fastqs,       '[\n\r]+', '')) as number_fastqs,
        trim(regexp_replace(results,             '[\n\r]+', '')) as results,
        trim(regexp_replace(trello,              '[\n\r]+', '')) as trello,
        trim(regexp_replace(notes,               '[\n\r]+', '')) as notes,
        trim(regexp_replace(todo,                '[\n\r]+', '')) as todo,
        trim(regexp_replace(sheet_name,          '[\n\r]+', '')) as sheet_name
    from
        source
    where
        coalesce
        (
            nullif(illumina_id, ''),
            nullif(run, ''),
            nullif("timestamp", ''),
            nullif(subject_id, ''),
            nullif(sample_id, ''),
            nullif(library_id, ''),
            nullif(external_subject_id, ''),
            nullif(external_sample_id, ''),
            nullif(external_library_id, ''),
            nullif(sample_name, ''),
            nullif(project_owner, ''),
            nullif(project_name, ''),
            nullif(project_custodian, ''),
            nullif(type, ''),
            nullif(assay, ''),
            nullif(override_cycles, ''),
            nullif(phenotype, ''),
            nullif(source, ''),
            nullif(quality, ''),
            nullif(topup, ''),
            nullif(secondary_analysis, ''),
            nullif(workflow, ''),
            nullif(tags, ''),
            nullif(fastq, ''),
            nullif(number_fastqs, ''),
            nullif(results, ''),
            nullif(trello, ''),
            nullif(notes, ''),
            nullif(todo, ''),
            nullif(sheet_name, '')
        ) is not null

),

transformed as (

    select
        illumina_id,
        cast(run as integer),
        cast("timestamp" as date) as "timestamp",
        subject_id,
        sample_id,
        library_id,
        external_subject_id,
        external_sample_id,
        external_library_id,
        sample_name,
        project_owner,
        project_name,
        project_custodian,
        type,
        assay,
        override_cycles,
        phenotype,
        source,
        quality,
        topup,
        secondary_analysis,
        workflow,
        tags,
        fastq,
        number_fastqs,
        results,
        trello,
        notes,
        todo,
        sheet_name,
        cast("timestamp" as timestamptz) + interval '11 hours' as load_datetime,
        'Google_LIMS' as record_source
    from
        cleaned

),

final as (

    select * from transformed

)

select * from final
