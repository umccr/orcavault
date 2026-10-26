{{
    config(
        on_schema_change='fail',
        dist='library_id',
        sort=['sheet_name', 'library_id']
    )
}}

with source as (

    {# Keep only the latest tracking sheet row per library_id (rn = 1 is the most recent load). #}

    select
        row_number() over (partition by library_id order by load_datetime desc) as rn,
        *
    from {{ ref('spreadsheet__library_tracking_metadata') }}

),

latest as (

    select * from source where rn = 1

),

filtered as (

    select *
    from latest
    where lower(run) like '%dns%'
       or lower(comments) like '%dns%'

),

aliased as (

    select
        src.*,
        sal.base_library_id,
        sal.alias_library_id
    from filtered src
        left join {{ ref('sal_library') }} sal on sal.alias_library_id = src.library_id

),

transformed as (

    select
        sheet_name,
        run,
        comments,
        coalesce(base_library_id, library_id) as library_id,
        alias_library_id,
        subject_id                            as internal_subject_id,
        external_subject_id,
        sample_id,
        external_sample_id,
        experiment_id,
        project_name                          as project_id,
        project_owner                         as owner_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index,
        record_source,
        load_datetime
    from aliased

),

final as (

    select
        cast(sheet_name          as varchar)      as sheet_name,
        cast(run                 as varchar)      as run,
        cast(comments            as varchar)      as comments,
        cast(library_id          as varchar(255)) as library_id,
        cast(alias_library_id    as varchar(255)) as alias_library_id,
        cast(internal_subject_id as varchar(255)) as internal_subject_id,
        cast(external_subject_id as varchar(255)) as external_subject_id,
        cast(sample_id           as varchar(255)) as sample_id,
        cast(external_sample_id  as varchar(255)) as external_sample_id,
        cast(experiment_id       as varchar(255)) as experiment_id,
        cast(project_id          as varchar(255)) as project_id,
        cast(owner_id            as varchar(255)) as owner_id,
        cast(workflow            as varchar(255)) as workflow,
        cast(phenotype           as varchar(255)) as phenotype,
        cast(type                as varchar(255)) as type,
        cast(assay               as varchar(255)) as assay,
        cast(quality             as varchar(255)) as quality,
        cast(source              as varchar(255)) as source,
        cast(truseq_index        as varchar(255)) as truseq_index,
        cast(record_source       as varchar(255)) as record_source,
        cast(load_datetime       as timestamptz)  as load_datetime
    from transformed
    order by sheet_name desc, library_id desc

)

select * from final
