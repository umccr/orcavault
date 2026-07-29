{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='library_sequencing_run_hk',
        sort=['library_sequencing_run_hk', 'load_datetime']
    )
}}

with seq_lookup as (

    select distinct
        orcabus_id,
        instrument_run_id
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}

),

cdc as (

    select
        seq.instrument_run_id   as sequencing_run_id,
        assoc.library_id        as library_id,
        assoc.orcabus_id        as orcabus_id,
        assoc.association_date  as association_date,
        assoc.status            as status,
        assoc.sequence_id       as sequence_id,
        assoc.op,
        assoc._dms_cdc_timestamp
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_libraryassociation') }} assoc
        join seq_lookup seq on seq.orcabus_id = assoc.sequence_id
    {% if is_incremental() %}
    where assoc._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

transformed as (

    select
        sha2(sequencing_run_id::varchar, 256)       as sequencing_run_hk,
        sha2(library_id::varchar, 256)              as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'sequence_run_manager_libraryassociation'   as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'association_date',
            'status',
            'sequence_id',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        association_date,
        status,
        sequence_id,
        op,
        _dms_cdc_timestamp
    from cdc

),

final as (

    select
        cast({{ generate_hash_diff(['sequencing_run_hk', 'library_hk']) }}
                                        as char(64))     as library_sequencing_run_hk,
        cast(load_datetime              as timestamptz)  as load_datetime,
        cast(record_source              as varchar(100)) as record_source,
        cast(hash_diff                  as char(64))     as hash_diff,
        cast(orcabus_id                 as char(26))     as orcabus_id,
        cast(association_date           as timestamptz)  as association_date,
        cast(status                     as varchar(255)) as status,
        cast(sequence_id                as char(26))     as sequence_id,
        cast(op                         as char(1))      as op,
        cast(_dms_cdc_timestamp         as timestamptz)  as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
