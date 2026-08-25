{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'library_id']
    )
}}

{#
    Note -
    This is the business vault "Computed Satellite" design pattern implementation. The intent is to do "data mining" on
    the well-known library_id pattern from analysis data output path. It returns all matches or NULL otherwise. Include
    the 'Undetermined' as expected for typical bcl_convert output.

    Since business satellite, it is ok to full refresh when business rule has changed or to cater for new requirements.
    The index size should be less hub_s3object Hub size; of which by design it should be the _compacted_ business key.
    So, the full refresh should be optimal and efficient ~1 minute for ~10 million (initial) load rate and, daily
    incremental for maintaining the index should be some _tiny_ seconds job for a couple of thousand records.

    Though the solution covers "the baseline" use cases well, it might be good to explore different solutions such as
    vector-oriented / inverted index on hub_s3object business key for relevancy search UX when needing to scale up more.
    And/or a deterministic DCL model linking via Workflow and Library data lineage.

    Please check with Victor on these more complex topics and solutions.
    ~victor

    Retrospective note -
    https://trello.com/c/OmhmlAkN/1426-orcabus-v1-design-and-implement-file-manager
    https://trello.com/c/LmqUfD4U/1368-portal-search-improve-global-search-implementation
    https://github.com/umccr/data-portal-apis/issues/343
#}

with numbers as (

    {{ generate_series(10) }}

),

source as (

    select
        s3object_hk,
        "key",
        load_datetime,
        record_source
    from
        {{ ref('hub_s3object') }}
    {% if is_incremental() %}
    where
        load_datetime > ( select coalesce(max(load_datetime), '1900-01-01') from {{ this }} )
    {% endif %}

),

flattened as (

    select
        s3object_hk,
        {{ extract_library_id_global('"key"') }}                               as library_id,
        load_datetime,
        record_source
    from
        source
        cross join numbers
    where
        {{ extract_library_id_global('"key"') }} is not null

),

deduped as (

    select
        s3object_hk,
        library_id,
        load_datetime,
        record_source
    from (
        select
            *,
            row_number() over (
                partition by s3object_hk, library_id
                order by load_datetime desc
            ) as rn
        from flattened
    ) t
    where rn = 1

),

filenames as (

    select
        s3object_hk,
        nullif(regexp_replace("key", '^.+[/\\]', ''), '')                   as filename
    from
        source

),

transformed as (

    select
        d.s3object_hk,
        cast('{{ run_started_at }}' as timestamptz)                         as load_datetime,
        d.record_source,
        {{ generate_hash_diff(['d.s3object_hk', 'd.library_id']) }}         as hash_diff,
        d.library_id,
        fn.filename,
        {{ split_part_from_right('fn.filename', '.', 1) }}                  as ext1,
        {{ split_part_from_right('fn.filename', '.', 2) }}                  as ext2,
        {{ split_part_from_right('fn.filename', '.', 3) }}                  as ext3,
        {{ split_part_from_right('fn.filename', '.', 4) }}                  as ext4
    from
        deduped d
        join filenames fn on fn.s3object_hk = d.s3object_hk

),

final as (

    select
        cast(s3object_hk    as char(64))                                    as s3object_hk,
        cast(load_datetime  as timestamptz)                                 as load_datetime,
        cast(record_source  as varchar(100))                                as record_source,
        cast(hash_diff      as char(64))                                    as hash_diff,
        cast(library_id     as varchar(255))                                as library_id,
        cast(filename       as varchar(1024))                               as filename,
        cast(ext1           as varchar(255))                                as ext1,
        cast(ext2           as varchar(255))                                as ext2,
        cast(ext3           as varchar(255))                                as ext3,
        cast(ext4           as varchar(255))                                as ext4
    from
        transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.s3object_hk = transformed.s3object_hk
          and t.hash_diff   = transformed.hash_diff
    )
    {% endif %}

)

select * from final
