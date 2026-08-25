{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['s3object_hk', 'hash_diff'],
        merge_update_columns=['effective_to', 'is_current', 'is_deleted'],
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'effective_from']
    )
}}

{#
    Note -
    This is the business transformation of history `sat_s3object_fm` model into "SCD Type 2" style or
    the "Current State Satellite" or "Point-in-Time Satellite" (DV2.0 nomenclature) design pattern. We
    do not carry all columns forward from "history" model to this "current" satellite model. Only that
    is needed (use case) and useful for the downstream data mart. Since this model's purpose is for a
    Business Vault layer, it can be rebuilt (--full-refresh) when business requirement has changed.
    Having said, we need to be mindful about the size of the data when needing to rebuild so.
    ~victor
#}

with incremental as (

    select
        distinct h.s3object_hk, h.version_id
    from
        {{ ref('sat_s3object_fm') }} h
    {% if is_incremental() %}
    where
        h.load_datetime > ( select coalesce(max(load_datetime), '1900-01-01') from {{ this }} )
    {% endif %}

),

deduped as (

    select
        h.*,
        row_number() over (
            partition by h.s3object_hk, h.hash_diff
            order by h.load_datetime desc
        ) as rank_by_history_ldts
    from
        {{ ref('sat_s3object_fm') }} h
        join incremental i
            on  i.s3object_hk = h.s3object_hk
            and i.version_id  = h.version_id

),

history as (

    select
        h.*,
        cast(is_current_state as smallint)                  as is_current_state__int,
        row_number() over (
            partition by h.s3object_hk, h.version_id
            order by h.event_time desc, h.sequencer desc
        ) as rank_by_group
    from
        deduped h
    where
        h.rank_by_history_ldts = 1

),

transformed as (

    select
        s3object_hk,
        cast('{{ run_started_at }}' as timestamptz)         as load_datetime,
        record_source,
        {{ generate_hash_diff([
            's3_object_id',
            '"size"',
            'e_tag',
            '"sha256"',
            'last_modified_date',
            'storage_class',
            'attributes',
            'ingest_id',
            'reason',
            'version_id',
            'is_current_state__int'
        ]) }}                                               as hash_diff,
        s3_object_id,
        "size",
        e_tag,
        "sha256",
        last_modified_date,
        storage_class,
        attributes,
        ingest_id,
        reason,
        version_id,
        is_current_state__int                               as version_active,
        cast(event_time as timestamptz)                     as effective_from,
        case
            when rank_by_group = 1 then
                cast('9999-12-31' as timestamptz)
            else
                lag(event_time) over (
                    partition by s3object_hk, version_id
                    order by rank_by_group
                )
        end                                                 as effective_to,
        case when rank_by_group = 1 then 1 else 0 end       as is_current,
        case when event_type = 'Deleted' then 1 else 0 end  as is_deleted
    from
        history

),

final as (

    select
        cast(s3object_hk        as char(64))            as s3object_hk,
        cast(load_datetime      as timestamptz)         as load_datetime,
        cast(record_source      as varchar(100))        as record_source,
        cast(hash_diff          as char(64))            as hash_diff,
        cast(s3_object_id       as varchar(36))         as s3_object_id,
        cast("size"             as bigint)              as "size",
        cast(e_tag              as varchar(255))        as e_tag,
        cast("sha256"           as varchar(255))        as "sha256",
        cast(last_modified_date as timestamptz)         as last_modified_date,
        cast(storage_class      as varchar(255))        as storage_class,
        cast(attributes         as varchar(1024))       as attributes,
        cast(ingest_id          as varchar(36))         as ingest_id,
        cast(reason             as varchar(255))        as reason,
        cast(version_id         as varchar(255))        as version_id,
        cast(version_active     as smallint)            as version_active,
        cast(effective_from     as timestamptz)         as effective_from,
        cast(effective_to       as timestamptz)         as effective_to,
        cast(is_current         as smallint)            as is_current,
        cast(is_deleted         as smallint)            as is_deleted
    from
        transformed

)

select * from final
