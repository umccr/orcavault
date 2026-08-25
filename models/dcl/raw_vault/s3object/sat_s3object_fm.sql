{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='s3object_hk',
        sort=['s3object_hk', 'load_datetime']
    )
}}

{#
    Note -
    This is the Raw Vault layer the standard satellite model for `hub_s3object` by upstream record source is being
    OrcaBus FileManager application. One highlight is that, the upstream app models after "append" only style data
    model. We then change data capture (CDC) tracks from upstream via DMS. So, it ends up of _history of history_ on
    change management tracking. Therefore, we would not expect to observe op = 'D' condition at all. When considering
    for DV2.0 append only satellite model (this one) over here, we do not need to replicate fine history tracking again
    specifically. We straight forward build per standard satellite model with the lastest snapshot of per load window
    changes on bucket, key, version_id partition. We already have _fine grain_ CDC history in S3 datalake that can be
    queryable via Athena for the _detailed_ history audit trail for the targeted bucket and key, if need be.
    ~victor
#}

with cdc as (

    select
        case
            when op = 'D' then 1
            when op = 'U' then 2
            when op = 'I' then 3
        end as op_order,
        *
    from
        {{ source('orcabus_filemanager', 's3_object') }}
    where
        "key" not like '%.iap_upload_test.tmp'
        and "key" not like '%.iap_xaccount_test.tmp'

    {% if is_incremental() %}
        and partition_0 >= (
            select to_char(
                dateadd(day, -1, max(load_datetime)::date),
                'YYYY'
            ) from {{ this }}
        )
        and partition_1 >= (
            select to_char(
                dateadd(day, -1, max(load_datetime)::date),
                'MM'
            ) from {{ this }}
        )
        and partition_2 >= (
            select to_char(
                dateadd(day, -1, max(load_datetime)::date),
                'DD'
            ) from {{ this }}
        )
        and _dms_cdc_timestamp > (select max(load_datetime) from {{ this }})
    {% endif %}

),

deduped as (

    select
        *
    from (
        select
            *,
            row_number() over (
                partition by bucket, "key", version_id
                order by _dms_cdc_timestamp desc, event_time desc, sequencer desc, op_order
                ) as rn
        from cdc
    ) t
    where rn = 1
),

transformed as (

    select
        {{ generate_s3object_hk('bucket', '"key"') }}   as s3object_hk,
        cast('{{ run_started_at }}' as timestamptz)     as load_datetime,
        'orcabus_filemanager_s3_object'                 as record_source,
        {{ generate_hash_diff([
            's3_object_id',
            'event_type',
            'version_id',
            'event_time',
            '"size"',
            'sha256',
            'last_modified_date',
            'e_tag',
            'storage_class',
            'sequencer',
            'is_delete_marker',
            'number_duplicate_events',
            'attributes',
            'deleted_date',
            'deleted_sequencer',
            'number_reordered',
            'ingest_id',
            'is_current_state',
            'reason',
            'archive_status',
            'is_accessible',
            'op',
            '_dms_cdc_timestamp'
        ]) }}                                           as hash_diff,
        s3_object_id,
        event_type,
        version_id,
        event_time,
        "size",
        sha256,
        last_modified_date,
        e_tag,
        storage_class,
        sequencer,
        {{cast_varchar_to_boolean('is_delete_marker')}} as is_delete_marker,
        number_duplicate_events,
        attributes,
        deleted_date,
        deleted_sequencer,
        number_reordered,
        ingest_id,
        {{cast_varchar_to_boolean('is_current_state')}} as is_current_state,
        reason,
        archive_status,
        {{cast_varchar_to_boolean('is_accessible')}}    as is_accessible,
        op,
        _dms_cdc_timestamp
    from deduped

),

final as (

    select
        cast(s3object_hk        as char(64))            as s3object_hk,
        cast(load_datetime      as timestamptz)         as load_datetime,
        cast(record_source      as varchar(100))        as record_source,
        cast(hash_diff          as char(64))            as hash_diff,
        cast(s3_object_id       as varchar(36))         as s3_object_id,
        cast(event_type         as varchar(255))        as event_type,
        cast(version_id         as varchar(255))        as version_id,
        cast(event_time         as timestamptz)         as event_time,
        cast("size"             as bigint)              as "size",
        cast("sha256"           as varchar(255))        as "sha256",
        cast(last_modified_date as timestamptz)         as last_modified_date,
        cast(e_tag              as varchar(255))        as e_tag,
        cast(storage_class      as varchar(255))        as storage_class,
        cast(sequencer          as varchar(255))        as sequencer,
        cast(is_delete_marker   as boolean)             as is_delete_marker,
        cast(number_duplicate_events as bigint)         as number_duplicate_events,
        cast(attributes         as varchar(1024))       as attributes,
        cast(deleted_date       as timestamptz)         as deleted_date,
        cast(deleted_sequencer  as varchar(255))        as deleted_sequencer,
        cast(number_reordered   as bigint)              as number_reordered,
        cast(ingest_id          as varchar(36))         as ingest_id,
        cast(is_current_state   as boolean)             as is_current_state,
        cast(reason             as varchar(255))        as reason,
        cast(archive_status     as varchar(255))        as archive_status,
        cast(is_accessible      as boolean)             as is_accessible,
        cast(op                 as char(1))             as op,
        cast(_dms_cdc_timestamp as timestamptz)         as _dms_cdc_timestamp
    from transformed
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} t
        where t.s3object_hk = transformed.s3object_hk
            and t.hash_diff = transformed.hash_diff
    )
    {% endif %}

)

select * from final
