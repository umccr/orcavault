{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='internal_external_subject_hk',
        sort=['internal_external_subject_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY BLOCK (one-off initial load)                          #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Priority order:                                              #}
{#   spreadsheet__library_tracking_metadata                     #}
{#   > spreadsheet__google_lims                                 #}
{#   > data_portal_labmetadata > data_portal_limsrow            #}
{#   > orcabus_metadata_manager                                 #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with legacy_source as (

    select distinct subject_id as internal_subject_id, trim(external_subject_id) as external_subject_id, 'legacy_data_portal_labmetadata'  as record_source from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}
    union all
    select distinct subject_id as internal_subject_id, trim(external_subject_id) as external_subject_id, 'legacy_data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select distinct subject_id as internal_subject_id, trim(external_subject_id) as external_subject_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select distinct internal_subject_id, external_subject_id, record_source
    from legacy_source
    where internal_subject_id is not null
      and internal_subject_id <> ''
      and external_subject_id is not null
      and external_subject_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Two active sources — spreadsheet PSA layer and CDC.          #}
{# CDC joins app_subject to app_individual via                  #}
{# app_subjectindividuallink junction table.                    #}
{# ============================================================ #}

spreadsheet_source as (

{% else %}

with spreadsheet_source as (

{% endif %}

    select distinct
        subject_id                                  as internal_subject_id,
        trim(external_subject_id)                   as external_subject_id,
        'spreadsheet__library_tracking_metadata'    as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_source as (

    select distinct
        idv.individual_id                           as internal_subject_id,
        sbj.subject_id                              as external_subject_id,
        'orcabus_metadata_manager'                  as record_source
    from {{ source('orcabus_metadata_manager', 'app_subjectindividuallink') }} lnk
        join {{ source('orcabus_metadata_manager', 'app_subject') }} sbj
            on sbj.orcabus_id = lnk.subject_orcabus_id
        join {{ source('orcabus_metadata_manager', 'app_individual') }} idv
            on idv.orcabus_id = lnk.individual_orcabus_id
    {% if is_incremental() %}
    where lnk._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select distinct internal_subject_id, external_subject_id, record_source
    from (
        select internal_subject_id, external_subject_id, record_source from spreadsheet_source
        union all
        select internal_subject_id, external_subject_id, record_source from cdc_source
    ) combined
    where internal_subject_id is not null
      and internal_subject_id <> ''
      and external_subject_id is not null
      and external_subject_id <> ''

),

merged as (

    {% if var('load_legacy', false) %}
    select internal_subject_id, external_subject_id, record_source
    from (
        select
            internal_subject_id,
            external_subject_id,
            record_source,
            row_number() over (
                partition by internal_subject_id, external_subject_id
                order by case record_source
                    when 'spreadsheet__library_tracking_metadata' then 1
                    when 'spreadsheet__google_lims'               then 2
                    when 'legacy_data_portal_labmetadata'         then 3
                    when 'legacy_data_portal_limsrow'             then 4
                    when 'orcabus_metadata_manager'               then 5
                    else 6
                end
            ) as rn
        from (
            select internal_subject_id, external_subject_id, record_source from legacy_cleaned
            union all
            select internal_subject_id, external_subject_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select internal_subject_id, external_subject_id, record_source
    from (
        select
            internal_subject_id,
            external_subject_id,
            record_source,
            row_number() over (
                partition by internal_subject_id, external_subject_id
                order by case record_source
                    when 'spreadsheet__library_tracking_metadata' then 1
                    when 'orcabus_metadata_manager'               then 2
                    else 3
                end
            ) as rn
        from active_cleaned
    ) t
    where rn = 1
    {% endif %}

),

transformed as (

    select
        sha2(internal_subject_id::varchar, 256)     as internal_subject_hk,
        sha2(external_subject_id::varchar, 256)     as external_subject_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source
    from merged

),

final as (

    select
        cast({{ generate_hash_diff(['external_subject_hk', 'internal_subject_hk']) }}
                                        as char(64))     as internal_external_subject_hk,
        cast(external_subject_hk        as char(64))     as external_subject_hk,
        cast(internal_subject_hk        as char(64))     as internal_subject_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.external_subject_hk = transformed.external_subject_hk
          and t.internal_subject_hk = transformed.internal_subject_hk
    )
    {% endif %}

)

select * from final
