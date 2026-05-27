{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'load_datetime']
    )
}}

with source as (

    select
        instrument_run_id as sequencing_run_id,
        orcabus_id,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        ica_project_id,
        v1pre3_id,
        sequence_run_id as basespace_run_id,
        experiment_name
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
    where
        end_time is not null
    {% if is_incremental() %}
    and
        cast(end_time as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        sha2(sequencing_run_id::varchar, 256) as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'sequence_run_manager_sequence') as record_source,

        {# FIXME create common method to a) cast to string b) concat them c) return sha2 #}
        sha2(
            coalesce(orcabus_id::varchar, '')        ||
            coalesce(status::varchar, '')            ||
            coalesce(start_time::varchar, '')        ||
            coalesce(end_time::varchar, '')          ||
            coalesce(reagent_barcode::varchar, '')   ||
            coalesce(flowcell_barcode::varchar, '')  ||
            coalesce(ica_project_id::varchar, '')    ||
            coalesce(v1pre3_id::varchar, '')         ||
            coalesce(basespace_run_id::varchar, '')  ||
            coalesce(experiment_name::varchar, '')
        , 256) AS hash_diff,

        orcabus_id,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        ica_project_id,
        v1pre3_id,
        basespace_run_id,
        experiment_name
    from
        source

),

final as (

    select
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as char(26)) as orcabus_id,
        cast(status as varchar(255)) as status,
        cast(start_time as timestamptz) as start_time,
        cast(end_time as timestamptz) as end_time,
        cast(reagent_barcode as varchar(255)) as reagent_barcode,
        cast(flowcell_barcode as varchar(255)) as flowcell_barcode,
        cast(ica_project_id as varchar(255)) as ica_project_id,
        cast(v1pre3_id as varchar(255)) as v1pre3_id,
        cast(basespace_run_id as varchar(255)) as basespace_run_id,
        cast(experiment_name as varchar(255)) as experiment_name
    from
        transformed

)

select * from final
