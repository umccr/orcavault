{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'load_datetime']
    )
}}

with source as (

    select
        usage_id,
        usage_hash,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        quantity as usage_quantity,
        usage_unit,
        price_per_unit,
        cost,
        cost_unit,
        category,
        usage_timestamp,
        region,
        ica_execution_id,
        case when nullif(license, '') is null then false else true end as is_license_cost,
        id_matches_reference,
        max(nullif(portal_run_id, '')) over (
            partition by ica_execution_id
        ) as resolved_run_id,
        billing_date,
        record_source
    from {{ ref('spreadsheet__ica_usage_report') }} as usage
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing
        where existing.usage_hash = usage.usage_hash
    )
    {% endif %}

),

hash_ready as (

    select
        *,
        case
            when is_license_cost then 'true'
            else 'false'
        end as is_license_cost_hash,
        case
            when id_matches_reference is null then null
            when id_matches_reference then 'true'
            else 'false'
        end as id_matches_reference_hash
    from source

),

transformed as (

    select
        sha2(resolved_run_id::varchar, 256)           as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz)   as load_datetime,
        record_source,
        {{ generate_hash_diff([
            'usage_id',
            'usage_hash',
            'usage_context',
            'usage_context_type',
            'user_name',
            'product',
            'usage_type_description',
            'usage_quantity',
            'usage_unit',
            'price_per_unit',
            'cost',
            'cost_unit',
            'category',
            'usage_timestamp',
            'region',
            'ica_execution_id',
            'is_license_cost_hash',
            'id_matches_reference_hash',
            'billing_date'
        ]) }}                                         as hash_diff,
        usage_id,
        usage_hash,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        usage_quantity,
        usage_unit,
        price_per_unit,
        cost,
        cost_unit,
        category,
        usage_timestamp,
        region,
        ica_execution_id,
        is_license_cost,
        id_matches_reference,
        billing_date
    from hash_ready
    where resolved_run_id is not null
      and usage_context not in ('development', 'staging')

),

final as (

    select
        cast(workflow_run_hk       as char(64))        as workflow_run_hk,
        cast(load_datetime         as timestamptz)     as load_datetime,
        cast(record_source         as varchar(100))    as record_source,
        cast(hash_diff             as char(64))        as hash_diff,
        cast(usage_id              as varchar(255))    as usage_id,
        cast(usage_hash            as char(64))        as usage_hash,
        cast(usage_context         as varchar(255))    as usage_context,
        cast(usage_context_type    as varchar(255))    as usage_context_type,
        cast(user_name             as varchar(255))    as user_name,
        cast(product               as varchar(255))    as product,
        cast(usage_type_description as varchar(255))   as usage_type_description,
        cast(usage_quantity        as numeric(38, 20)) as usage_quantity,
        cast(usage_unit            as varchar(255))    as usage_unit,
        cast(price_per_unit        as numeric(25, 20)) as price_per_unit,
        cast(cost                  as numeric(25, 20)) as cost,
        cast(cost_unit             as varchar(255))    as cost_unit,
        cast(category              as varchar(255))    as category,
        cast(usage_timestamp       as date)            as usage_timestamp,
        cast(region                as varchar(255))    as region,
        cast(ica_execution_id      as varchar(255))    as ica_execution_id,
        cast(is_license_cost       as boolean)         as is_license_cost,
        cast(id_matches_reference  as boolean)         as id_matches_reference,
        cast(billing_date          as date)            as billing_date
    from transformed

)

select * from final
