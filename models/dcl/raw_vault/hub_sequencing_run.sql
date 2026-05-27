{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sequencing_run_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'last_seen_datetime']
    )
}}

with source as (

    {# FIXME a) change incremental load b) legacy load one-off #}
    select instrument_run_id as sequencing_run_id from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}

),

cleaned as (

    select * from source where sequencing_run_id is not null and sequencing_run_id <> ''

),

differentiated as (

    select distinct sequencing_run_id from cleaned
    {% if is_incremental() %}
    except
    select sequencing_run_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        sha2(sequencing_run_id::varchar, 256) as sequencing_run_hk,
        sequencing_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
