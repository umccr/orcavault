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
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Priority order:                                              #}
{#   spreadsheet__google_lims                                   #}
{#   > data_portal_libraryrun > data_portal_limsrow             #}
{#   > orcabus_sequence_run_manager                             #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select distinct library_id, instrument_run_id as sequencing_run_id, 'legacy_data_portal_libraryrun'   as record_source from {{ source('data_portal', 'legacy_data_portal_libraryrun') }}
    union all
    select distinct library_id, illumina_id       as sequencing_run_id, 'legacy_data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select distinct library_id, illumina_id       as sequencing_run_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select distinct library_id, sequencing_run_id, record_source
    from legacy_source
    where library_id is not null
      and library_id <> ''
      and sequencing_run_id is not null
      and sequencing_run_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# CDC joins sequence_run_manager_sequence to                   #}
{# sequence_run_manager_libraryassociation.                     #}
{# Incremental watermark on libraryassociation._dms_cdc_timestamp#}
{# ============================================================ #}

cdc_source as (

{% else %}

with cdc_source as (

{% endif %}

    select distinct
        assoc.library_id,
        seq.instrument_run_id                       as sequencing_run_id,
        'orcabus_sequence_run_manager'              as record_source
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_libraryassociation') }} assoc
        join {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }} seq
            on seq.orcabus_id = assoc.sequence_id
    {% if is_incremental() %}
    where assoc._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select distinct library_id, sequencing_run_id, record_source
    from cdc_source
    where library_id is not null
      and library_id <> ''
      and sequencing_run_id is not null
      and sequencing_run_id <> ''

),

merged as (

    {% if var('load_legacy', false) %}
    select library_id, sequencing_run_id, record_source
    from (
        select
            library_id,
            sequencing_run_id,
            record_source,
            row_number() over (
                partition by library_id, sequencing_run_id
                order by case record_source
                    when 'spreadsheet__google_lims'          then 1
                    when 'legacy_data_portal_libraryrun'     then 2
                    when 'legacy_data_portal_limsrow'        then 3
                    when 'orcabus_sequence_run_manager'      then 4
                    else 5
                end
            ) as rn
        from (
            select library_id, sequencing_run_id, record_source from legacy_cleaned
            union all
            select library_id, sequencing_run_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select library_id, sequencing_run_id, record_source from active_cleaned
    {% endif %}

),

transformed as (

    select
        sha2(library_id::varchar, 256)              as library_hk,
        sha2(sequencing_run_id::varchar, 256)       as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source
    from merged

),

final as (

    select
        cast({{ generate_hash_diff(['sequencing_run_hk', 'library_hk']) }}
                                        as char(64))     as library_sequencing_run_hk,
        cast(sequencing_run_hk          as char(64))     as sequencing_run_hk,
        cast(library_hk                 as char(64))     as library_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.sequencing_run_hk = transformed.sequencing_run_hk
          and t.library_hk = transformed.library_hk
    )
    {% endif %}

)

select * from final
