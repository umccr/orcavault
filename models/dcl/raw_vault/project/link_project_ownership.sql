{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='project_owner_hk',
        sort=['project_owner_hk', 'load_datetime']
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

    select distinct trim(project_name) as project_id, trim(project_owner) as owner_id, 'legacy_data_portal_labmetadata'  as record_source from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}
    union all
    select distinct trim(project_name) as project_id, trim(project_owner) as owner_id, 'legacy_data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select distinct trim(project_name) as project_id, trim(project_owner) as owner_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select distinct project_id, owner_id, record_source
    from legacy_source
    where project_id is not null
      and project_id <> ''
      and owner_id is not null
      and owner_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Two active sources — spreadsheet PSA layer and CDC.          #}
{# CDC joins app_project to app_contact via                     #}
{# app_projectcontactlink junction table.                       #}
{# ============================================================ #}

spreadsheet_source as (

{% else %}

with spreadsheet_source as (

{% endif %}

    select distinct
        trim(project_name)                          as project_id,
        trim(project_owner)                         as owner_id,
        'spreadsheet__library_tracking_metadata'    as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_source as (

    select distinct
        prj.project_id,
        cnt.contact_id                              as owner_id,
        'orcabus_metadata_manager'                  as record_source
    from {{ source('orcabus_metadata_manager', 'app_projectcontactlink') }} lnk
        join {{ source('orcabus_metadata_manager', 'app_project') }} prj
            on prj.orcabus_id = lnk.project_orcabus_id
        join {{ source('orcabus_metadata_manager', 'app_contact') }} cnt
            on cnt.orcabus_id = lnk.contact_orcabus_id
    {% if is_incremental() %}
    where lnk._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select distinct project_id, owner_id, record_source
    from (
        select project_id, owner_id, record_source from spreadsheet_source
        union all
        select project_id, owner_id, record_source from cdc_source
    ) combined
    where project_id is not null
      and project_id <> ''
      and owner_id is not null
      and owner_id <> ''

),

merged as (

    {% if var('load_legacy', false) %}
    select project_id, owner_id, record_source
    from (
        select
            project_id,
            owner_id,
            record_source,
            row_number() over (
                partition by project_id, owner_id
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
            select project_id, owner_id, record_source from legacy_cleaned
            union all
            select project_id, owner_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select project_id, owner_id, record_source
    from (
        select
            project_id,
            owner_id,
            record_source,
            row_number() over (
                partition by project_id, owner_id
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
        sha2(project_id::varchar, 256)              as project_hk,
        sha2(owner_id::varchar, 256)                as owner_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source
    from merged

),

final as (

    select
        cast({{ generate_hash_diff(['owner_hk', 'project_hk']) }}
                                    as char(64))        as project_owner_hk,
        cast(owner_hk               as char(64))        as owner_hk,
        cast(project_hk             as char(64))        as project_hk,
        cast(load_datetime          as timestamptz)     as load_datetime,
        cast(record_source          as varchar(100))    as record_source
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.owner_hk = transformed.owner_hk
          and t.project_hk = transformed.project_hk
    )
    {% endif %}

)

select * from final
