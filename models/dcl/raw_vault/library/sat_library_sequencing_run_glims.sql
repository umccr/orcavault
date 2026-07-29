{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='library_sequencing_run_hk',
        sort=['library_sequencing_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Frozen source — do not re-run after initial load.            #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with source as (

    select
        illumina_id     as sequencing_run_id,
        library_id,
        record_source,
        cast("timestamp" as date) as lims_timestamp,
        "run",
        override_cycles,
        secondary_analysis,
        number_fastqs,
        fastq,
        results,
        notes,
        trello
    from {{ ref('spreadsheet__google_lims') }}
    where (library_id is not null and library_id <> '')
      and (illumina_id is not null and illumina_id <> '')

),

transformed as (

    select
        sha2(sequencing_run_id::varchar, 256)       as sequencing_run_hk,
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'lims_timestamp',
            '"run"',
            'override_cycles',
            'secondary_analysis',
            'number_fastqs',
            'fastq',
            'results',
            'notes',
            'trello'
        ]) }}                                       as hash_diff,
        lims_timestamp,
        "run",
        override_cycles,
        secondary_analysis,
        number_fastqs,
        fastq,
        results,
        notes,
        trello
    from source

),

deduped as (

    select
        *
    from (
        select
            *,
            row_number() over (
                partition by sequencing_run_hk, library_hk, hash_diff
                order by lims_timestamp desc
            ) as rn
        from transformed
    ) t
    where rn = 1
),

final as (

    select
        cast({{ generate_hash_diff(['sequencing_run_hk', 'library_hk']) }}
                                            as char(64))      as library_sequencing_run_hk,
        cast(load_datetime                  as timestamptz)   as load_datetime,
        cast(record_source                  as varchar(100))  as record_source,
        cast(hash_diff                      as char(64))      as hash_diff,
        cast(lims_timestamp                 as date)          as lims_timestamp,
        cast("run"                          as integer)       as "run",
        cast(override_cycles                as varchar(64))   as override_cycles,
        cast(secondary_analysis             as varchar(64))   as secondary_analysis,
        cast(number_fastqs                  as varchar(8))    as number_fastqs,
        cast(fastq                          as varchar(255))  as fastq,
        cast(results                        as varchar(255))  as results,
        cast(notes                          as varchar(512))  as notes,
        cast(trello                         as varchar(255))  as trello
    from deduped

)

select * from final

{% else %}

{# ============================================================ #}
{# No-op on daily runs — legacy source is frozen.               #}
{# ============================================================ #}

select
    cast(null as char(64))      as library_sequencing_run_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as date)          as lims_timestamp,
    cast(null as integer)       as "run",
    cast(null as varchar(64))   as override_cycles,
    cast(null as varchar(64))   as secondary_analysis,
    cast(null as varchar(8))    as number_fastqs,
    cast(null as varchar(255))  as fastq,
    cast(null as varchar(255))  as results,
    cast(null as varchar(512))  as notes,
    cast(null as varchar(255))  as trello
where 1 = 0

{% endif %}
