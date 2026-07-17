{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='internal_external_sample_hk',
        sort=['internal_external_sample_hk', 'load_datetime']
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

    select distinct sample_id, trim(external_sample_id) as external_sample_id, 'legacy_data_portal_labmetadata'  as record_source from {{ source('data_portal', 'legacy_data_portal_labmetadata') }}
    union all
    select distinct sample_id, trim(external_sample_id) as external_sample_id, 'legacy_data_portal_limsrow'      as record_source from {{ source('data_portal', 'legacy_data_portal_limsrow') }}
    union all
    select distinct sample_id, trim(external_sample_id) as external_sample_id, 'spreadsheet__google_lims' as record_source from {{ ref('spreadsheet__google_lims') }}

),

legacy_cleaned as (

    select distinct sample_id, external_sample_id, record_source
    from legacy_source
    where sample_id is not null
      and sample_id <> ''
      and external_sample_id is not null
      and external_sample_id <> ''

),

{# ============================================================ #}
{# ACTIVE BLOCK (daily incremental)                             #}
{# Two active sources — spreadsheet PSA layer and CDC.          #}
{# ============================================================ #}

spreadsheet_source as (

{% else %}

with spreadsheet_source as (

{% endif %}

    select distinct
        sample_id,
        trim(external_sample_id)                    as external_sample_id,
        'spreadsheet__library_tracking_metadata'    as record_source
    from {{ ref('spreadsheet__library_tracking_metadata') }}
    {% if is_incremental() %}
    where load_datetime > (select max(load_datetime) from {{ this }})
    {% endif %}

),

cdc_source as (

    select distinct
        sample_id,
        trim(external_sample_id)                    as external_sample_id,
        'orcabus_metadata_manager'                  as record_source
    from {{ source('orcabus_metadata_manager', 'app_sample') }}
    {% if is_incremental() %}
    where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

active_cleaned as (

    select distinct sample_id, external_sample_id, record_source
    from (
        select sample_id, external_sample_id, record_source from spreadsheet_source
        union all
        select sample_id, external_sample_id, record_source from cdc_source
    ) combined
    where sample_id is not null
      and sample_id <> ''
      and external_sample_id is not null
      and external_sample_id <> ''

),

merged as (

    {% if var('load_legacy', false) %}
    select sample_id, external_sample_id, record_source
    from (
        select
            sample_id,
            external_sample_id,
            record_source,
            row_number() over (
                partition by sample_id, external_sample_id
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
            select sample_id, external_sample_id, record_source from legacy_cleaned
            union all
            select sample_id, external_sample_id, record_source from active_cleaned
        ) combined
    ) t
    where rn = 1
    {% else %}
    select sample_id, external_sample_id, record_source
    from (
        select
            sample_id,
            external_sample_id,
            record_source,
            row_number() over (
                partition by sample_id, external_sample_id
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
        sha2(sample_id::varchar, 256)               as sample_hk,
        sha2(external_sample_id::varchar, 256)      as external_sample_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source
    from merged

),

final as (

    select
        cast({{ generate_hash_diff(['external_sample_hk', 'sample_hk']) }}
                                        as char(64))     as internal_external_sample_hk,
        cast(external_sample_hk         as char(64))     as external_sample_hk,
        cast(sample_hk                  as char(64))     as sample_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.external_sample_hk = transformed.external_sample_hk
          and t.sample_hk = transformed.sample_hk
    )
    {% endif %}

)

select * from final
