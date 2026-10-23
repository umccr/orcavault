{{
    config(
        on_schema_change='fail',
        dist='library_id',
        sort=['library_id', 'alias_library_id']
    )
}}

with source as (

    {# Keep only the latest tracking sheet row per library_id (rn = 1 is the most recent load). #}

    select
        row_number() over (partition by library_id order by load_datetime desc) as rn,
        library_id,
        run,
        sheet_name,
        comments,
        record_source,
        load_datetime
    from {{ ref('spreadsheet__library_tracking_metadata') }}

),

transformed as (

    select
        sal.base_library_id as library_id,
        sal.alias_library_id,
        src.run,
        src.sheet_name,
        src.comments,
        src.record_source,
        src.load_datetime
    from {{ ref('sal_library') }} sal
        join source src
            on src.library_id = sal.alias_library_id
           and src.rn = 1

),

final as (

    select
        cast(library_id       as varchar(255)) as library_id,
        cast(alias_library_id as varchar(255)) as alias_library_id,
        cast(run              as varchar)      as run,
        cast(sheet_name       as varchar)      as sheet_name,
        cast(comments         as varchar)      as comments,
        cast(record_source    as varchar(255)) as record_source,
        cast(load_datetime    as timestamptz)  as load_datetime
    from transformed
    order by library_id desc

)

select * from final
