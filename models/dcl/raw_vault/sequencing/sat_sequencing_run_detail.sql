{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'load_datetime']
    )
}}

with cdc_deduplicated as (

    {# ======================================================== #}
    {# Deduplicate CDC events to one effective row per          #}
    {# instrument_run_id per day — the latest CDC event of      #}
    {# that day wins regardless of op type (I, U, D).           #}
    {# This produces one daily snapshot per sequencing run.     #}
    {# The op signal of the latest event is preserved for       #}
    {# downstream business vault is_deleted derivation.         #}
    {# ======================================================== #}

    select
        instrument_run_id,
        orcabus_id,
        run_volume_name,
        run_folder_path,
        run_data_uri,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        sample_sheet_name,
        sequence_run_id     as basespace_run_id,
        sequence_run_name,
        v1pre3_id,
        ica_project_id,
        api_url,
        experiment_name,
        op,
        _dms_cdc_timestamp
    from (
        select
            *,
            row_number() over (
                partition by instrument_run_id,
                             cast(_dms_cdc_timestamp as date)
                order by _dms_cdc_timestamp desc
            ) as rn
        from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
        {% if is_incremental() %}
        where _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
        {% endif %}
    ) t
    where rn = 1

),

transformed as (

    select
        sha2(instrument_run_id::varchar, 256)       as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'sequence_run_manager_sequence'             as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'run_volume_name',
            'run_folder_path',
            'run_data_uri',
            'status',
            'start_time',
            'end_time',
            'reagent_barcode',
            'flowcell_barcode',
            'sample_sheet_name',
            'basespace_run_id',
            'sequence_run_name',
            'v1pre3_id',
            'ica_project_id',
            'api_url',
            'experiment_name',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        run_volume_name,
        run_folder_path,
        run_data_uri,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        sample_sheet_name,
        basespace_run_id,
        sequence_run_name,
        v1pre3_id,
        ica_project_id,
        api_url,
        experiment_name,
        op,
        _dms_cdc_timestamp
    from cdc_deduplicated

),

final as (

    select
        cast(sequencing_run_hk      as char(64))         as sequencing_run_hk,
        cast(load_datetime          as timestamptz)      as load_datetime,
        cast(record_source          as varchar(100))     as record_source,
        cast(hash_diff              as char(64))         as hash_diff,
        cast(orcabus_id             as char(26))         as orcabus_id,
        cast(run_volume_name        as varchar(255))     as run_volume_name,
        cast(run_folder_path        as varchar(255))     as run_folder_path,
        cast(run_data_uri           as varchar(255))     as run_data_uri,
        cast(status                 as varchar(255))     as status,
        cast(start_time             as timestamptz)      as start_time,
        cast(end_time               as timestamptz)      as end_time,
        cast(reagent_barcode        as varchar(255))     as reagent_barcode,
        cast(flowcell_barcode       as varchar(255))     as flowcell_barcode,
        cast(sample_sheet_name      as varchar(255))     as sample_sheet_name,
        cast(basespace_run_id       as varchar(255))     as basespace_run_id,
        cast(sequence_run_name      as varchar(255))     as sequence_run_name,
        cast(v1pre3_id              as varchar(255))     as v1pre3_id,
        cast(ica_project_id         as varchar(255))     as ica_project_id,
        cast(api_url                as varchar(255))     as api_url,
        cast(experiment_name        as varchar(255))     as experiment_name,
        cast(op                     as char(1))          as op,
        cast(_dms_cdc_timestamp     as timestamptz)      as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
