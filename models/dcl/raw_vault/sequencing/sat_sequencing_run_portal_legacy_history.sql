{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'load_datetime']
    )
}}

{# ============================================================ #}
{# LEGACY ONE-OFF INITIAL LOAD ONLY                             #}
{# Activated by passing --vars '{"load_legacy": true}'          #}
{# Frozen source — do not re-run after initial load.            #}
{# ============================================================ #}

{% if var('load_legacy', false) %}

with source as (

    select distinct
        instrument_run_id,
        id,
        run_id,
        date_modified,
        status,
        gds_folder_path,
        gds_volume_name,
        reagent_barcode,
        v1pre3_id,
        acl,
        flowcell_barcode,
        sample_sheet_name,
        api_url,
        name,
        msg_attr_action,
        msg_attr_action_type,
        msg_attr_action_date,
        msg_attr_produced_by
    from {{ source('data_portal', 'legacy_data_portal_sequencerun') }}
    where instrument_run_id is not null
      and instrument_run_id <> ''

),

transformed as (

    select
        sha2(instrument_run_id::varchar, 256)       as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'legacy_data_portal_sequencerun'            as record_source,
        {{ generate_hash_diff([
            'id',
            'run_id',
            'date_modified',
            'status',
            'gds_folder_path',
            'gds_volume_name',
            'reagent_barcode',
            'v1pre3_id',
            'acl',
            'flowcell_barcode',
            'sample_sheet_name',
            'api_url',
            'name',
            'msg_attr_action',
            'msg_attr_action_type',
            'msg_attr_action_date',
            'msg_attr_produced_by'
        ]) }}                                       as hash_diff,
        id,
        run_id,
        date_modified,
        status,
        gds_folder_path,
        gds_volume_name,
        reagent_barcode,
        v1pre3_id,
        acl,
        flowcell_barcode,
        sample_sheet_name,
        api_url,
        name,
        msg_attr_action,
        msg_attr_action_type,
        msg_attr_action_date,
        msg_attr_produced_by
    from source

),

final as (

    select
        cast(sequencing_run_hk      as char(64))         as sequencing_run_hk,
        cast(load_datetime          as timestamptz)      as load_datetime,
        cast(record_source          as varchar(100))     as record_source,
        cast(hash_diff              as char(64))         as hash_diff,
        cast(id                     as bigint)           as id,
        cast(run_id                 as varchar(255))     as run_id,
        cast(date_modified          as timestamptz)      as date_modified,
        cast(status                 as varchar(255))     as status,
        cast(gds_folder_path        as varchar(255))     as gds_folder_path,
        cast(gds_volume_name        as varchar(255))     as gds_volume_name,
        cast(reagent_barcode        as varchar(255))     as reagent_barcode,
        cast(v1pre3_id              as varchar(255))     as v1pre3_id,
        cast(acl                    as varchar(255))     as acl,
        cast(flowcell_barcode       as varchar(255))     as flowcell_barcode,
        cast(sample_sheet_name      as varchar(255))     as sample_sheet_name,
        cast(api_url                as varchar(255))     as api_url,
        cast(name                   as varchar(255))     as name,
        cast(msg_attr_action        as varchar(255))     as msg_attr_action,
        cast(msg_attr_action_type   as varchar(255))     as msg_attr_action_type,
        cast(msg_attr_action_date   as varchar(255))     as msg_attr_action_date,
        cast(msg_attr_produced_by   as varchar(255))     as msg_attr_produced_by
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final

{% else %}

{# ============================================================ #}
{# No-op on daily runs — legacy source is frozen.               #}
{# ============================================================ #}

select
    cast(null as char(64))      as sequencing_run_hk,
    cast(null as timestamptz)   as load_datetime,
    cast(null as varchar(100))  as record_source,
    cast(null as char(64))      as hash_diff,
    cast(null as bigint)        as id,
    cast(null as varchar(255))  as run_id,
    cast(null as timestamptz)   as date_modified,
    cast(null as varchar(255))  as status,
    cast(null as varchar(255))  as gds_folder_path,
    cast(null as varchar(255))  as gds_volume_name,
    cast(null as varchar(255))  as reagent_barcode,
    cast(null as varchar(255))  as v1pre3_id,
    cast(null as varchar(255))  as acl,
    cast(null as varchar(255))  as flowcell_barcode,
    cast(null as varchar(255))  as sample_sheet_name,
    cast(null as varchar(255))  as api_url,
    cast(null as varchar(255))  as name,
    cast(null as varchar(255))  as msg_attr_action,
    cast(null as varchar(255))  as msg_attr_action_type,
    cast(null as varchar(255))  as msg_attr_action_date,
    cast(null as varchar(255))  as msg_attr_produced_by
where 1 = 0

{% endif %}
