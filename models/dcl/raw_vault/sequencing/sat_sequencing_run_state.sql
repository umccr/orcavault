{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='sequencing_run_hk',
        sort=['sequencing_run_hk', 'load_datetime']
    )
}}

with seq_lookup as (

    select distinct
        orcabus_id,
        instrument_run_id
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}

),

source as (

    {# ======================================================== #}
    {# All state records within the incremental window.         #}
    {# No daily dedup — raw vault keeps full state history.     #}
    {# Business vault handles state transition derivation.      #}
    {# ======================================================== #}

    select
        seq.instrument_run_id,
        stt.orcabus_id,
        stt.status,
        stt.timestamp       as state_timestamp,
        stt.comment,
        stt.sequence_id,
        stt.op,
        stt._dms_cdc_timestamp
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_state') }} stt
        join seq_lookup seq on seq.orcabus_id = stt.sequence_id
    {% if is_incremental() %}
    where stt._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

transformed as (

    select
        sha2(instrument_run_id::varchar, 256)       as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'sequence_run_manager_state'                as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'status',
            'state_timestamp',
            'comment',
            'sequence_id',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        status,
        state_timestamp,
        comment,
        sequence_id,
        op,
        _dms_cdc_timestamp
    from source

),

final as (

    select
        cast(sequencing_run_hk  as char(64))         as sequencing_run_hk,
        cast(load_datetime      as timestamptz)      as load_datetime,
        cast(record_source      as varchar(100))     as record_source,
        cast(hash_diff          as char(64))         as hash_diff,
        cast(orcabus_id         as char(26))         as orcabus_id,
        cast(status             as varchar(255))     as status,
        cast(state_timestamp    as timestamptz)      as state_timestamp,
        cast(comment            as varchar(1024))    as comment,
        cast(sequence_id        as char(26))         as sequence_id,
        cast(op                 as char(1))          as op,
        cast(_dms_cdc_timestamp as timestamptz)      as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
