{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['filename', 'ext1', 'ext2', 'ext3', 'ext4'],
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'portal_run_id', 'sequencing_run_id']
    )
}}

{#
    Note -
    This is the business vault "Computed Satellite" design pattern implementation. The intent is to do "data mining" on
    the well-known ID patterns and extensions from the data output path. ID return a single match or NULL otherwise.

    Since business satellite, it is OK to fully refresh when business rule has changed or to cater for new requirements.
    The index size is as much as hub_s3object Hub index size; of which by design it should be the _compacted_ business
    key. So, the full refresh should be optimal and efficient ~1 minute for ~10 million (initial) load rate and, daily
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

    Additional note -
    The difference between `sat_s3object_by_run` Vs `sat_s3object_by_library` - Choose ByLibrary table for implementing
    Library-driven use cases. Choose ByRun satellite for Run-driven use cases plus its extensions (ext1, ..., ext4)
    for any other use cases. The ByRun computed satellite should be tallied matched with the hub_s3object Hub count. The
    ByLibrary computed satellite would be scoped only to well-known library_id pattern.
#}

with source as (

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

extracted as (

    select
        s3object_hk,
        {{ extract_portal_run_id('"key"') }}                                as portal_run_id,
        {{ extract_sequencing_run_id('"key"') }}                            as sequencing_run_id,
        load_datetime,
        record_source
    from
        source

),

deduped as (

    select
        s3object_hk,
        portal_run_id,
        sequencing_run_id,
        load_datetime,
        record_source
    from (
        select
            *,
            row_number() over (
                partition by s3object_hk, portal_run_id, sequencing_run_id
                order by load_datetime desc
            ) as rn
        from extracted
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
        {{ generate_hash_diff(['d.s3object_hk', 'd.portal_run_id', 'd.sequencing_run_id']) }} as hash_diff,
        d.portal_run_id,
        d.sequencing_run_id,
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
        cast(s3object_hk        as char(64))                                as s3object_hk,
        cast(load_datetime      as timestamptz)                             as load_datetime,
        cast(record_source      as varchar(100))                            as record_source,
        cast(hash_diff          as char(64))                                as hash_diff,
        cast(portal_run_id      as char(16))                                as portal_run_id,
        cast(sequencing_run_id  as varchar(255))                            as sequencing_run_id,
        cast(filename           as varchar(1024))                           as filename,
        cast(ext1               as varchar(255))                            as ext1,
        cast(ext2               as varchar(255))                            as ext2,
        cast(ext3               as varchar(255))                            as ext3,
        cast(ext4               as varchar(255))                            as ext4
    from
        transformed

)

select * from final
