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
    {# All comment records within the incremental window.       #}
    {# No daily dedup — raw vault keeps full comment history.   #}
    {# Business vault handles latest comment derivation.        #}
    {# ======================================================== #}

    select
        seq.instrument_run_id,
        cmt.orcabus_id,
        cmt.comment,
        cmt.target_id,
        cmt.created_at,
        cmt.created_by,
        cmt.updated_at,
        cmt.is_deleted,
        cmt.target_type,
        cmt.op,
        cmt._dms_cdc_timestamp
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_comment') }} cmt
        join seq_lookup seq on seq.orcabus_id = cmt.target_id
    {% if is_incremental() %}
    where cmt._dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

transformed as (

    select
        sha2(instrument_run_id::varchar, 256)       as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'sequence_run_manager_comment'              as record_source,
        {{ generate_hash_diff([
            'orcabus_id',
            'comment',
            'target_id',
            'created_at',
            'created_by',
            'updated_at',
            'is_deleted',
            'target_type',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                       as hash_diff,
        orcabus_id,
        comment,
        target_id,
        created_at,
        created_by,
        updated_at,
        is_deleted,
        target_type,
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
        cast(comment            as varchar(1024))    as comment,
        cast(target_id          as char(26))         as target_id,
        cast(created_at         as timestamptz)      as created_at,
        cast(created_by         as varchar(255))     as created_by,
        cast(updated_at         as timestamptz)      as updated_at,
        cast(is_deleted         as varchar(255))     as is_deleted,
        cast(target_type        as varchar(255))     as target_type,
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
