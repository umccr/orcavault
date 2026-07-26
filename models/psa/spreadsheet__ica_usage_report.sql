{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        usage_id,
        uc_name,
        billable_account_id,
        account_name,
        account_type,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        quantity,
        usage_unit,
        price_per_unit,
        cost,
        cost_unit,
        category,
        usage_timestamp,
        region,
        metadata,
        billing_date,
        ica_execution_id,
        license,
        pipeline_uuid,
        status,
        domain,
        type,
        workflow_name,
        workflow_version,
        portal_run_id,
        ref_format,
        reference_raw,
        ref_uuid,
        id_matches_reference
    from
        {{ source('tsa', 'spreadsheet__ica_usage_report') }}

),

cleaned as (

    select
        trim(regexp_replace(usage_id,              '[\n\r]+', '')) as usage_id,
        trim(regexp_replace(uc_name,               '[\n\r]+', '')) as uc_name,
        trim(regexp_replace(billable_account_id,   '[\n\r]+', '')) as billable_account_id,
        trim(regexp_replace(account_name,          '[\n\r]+', '')) as account_name,
        trim(regexp_replace(account_type,          '[\n\r]+', '')) as account_type,
        trim(regexp_replace(usage_context,         '[\n\r]+', '')) as usage_context,
        trim(regexp_replace(usage_context_type,    '[\n\r]+', '')) as usage_context_type,
        trim(regexp_replace(user_name,             '[\n\r]+', '')) as user_name,
        trim(regexp_replace(product,               '[\n\r]+', '')) as product,
        trim(regexp_replace(usage_type_description, '[\n\r]+', '')) as usage_type_description,
        trim(regexp_replace(quantity,              '[\n\r]+', '')) as quantity,
        trim(regexp_replace(usage_unit,            '[\n\r]+', '')) as usage_unit,
        trim(regexp_replace(price_per_unit,        '[\n\r]+', '')) as price_per_unit,
        trim(regexp_replace(cost,                  '[\n\r]+', '')) as cost,
        trim(regexp_replace(cost_unit,             '[\n\r]+', '')) as cost_unit,
        trim(regexp_replace(category,              '[\n\r]+', '')) as category,
        trim(regexp_replace(usage_timestamp,       '[\n\r]+', '')) as usage_timestamp,
        trim(regexp_replace(region,                '[\n\r]+', '')) as region,
        trim(regexp_replace(metadata,              '[\n\r]+', '')) as metadata,
        trim(regexp_replace(billing_date,          '[\n\r]+', '')) as billing_date,
        trim(regexp_replace(ica_execution_id,      '[\n\r]+', '')) as ica_execution_id,
        trim(regexp_replace(license,               '[\n\r]+', '')) as license,
        trim(regexp_replace(pipeline_uuid,         '[\n\r]+', '')) as pipeline_uuid,
        trim(regexp_replace(status,                '[\n\r]+', '')) as status,
        trim(regexp_replace(domain,                '[\n\r]+', '')) as domain,
        trim(regexp_replace(type,                  '[\n\r]+', '')) as type,
        trim(regexp_replace(workflow_name,         '[\n\r]+', '')) as workflow_name,
        trim(regexp_replace(workflow_version,      '[\n\r]+', '')) as workflow_version,
        trim(regexp_replace(portal_run_id,         '[\n\r]+', '')) as portal_run_id,
        trim(regexp_replace(ref_format,            '[\n\r]+', '')) as ref_format,
        trim(regexp_replace(reference_raw,         '[\n\r]+', '')) as reference_raw,
        trim(regexp_replace(ref_uuid,              '[\n\r]+', '')) as ref_uuid,
        trim(regexp_replace(id_matches_reference,  '[\n\r]+', '')) as id_matches_reference
    from
        source

),

non_empty as (

    select
        *
    from
        cleaned
    where
        coalesce
        (
            nullif(usage_id, ''),
            nullif(uc_name, ''),
            nullif(billable_account_id, ''),
            nullif(account_name, ''),
            nullif(account_type, ''),
            nullif(usage_context, ''),
            nullif(usage_context_type, ''),
            nullif(user_name, ''),
            nullif(product, ''),
            nullif(usage_type_description, ''),
            nullif(quantity, ''),
            nullif(usage_unit, ''),
            nullif(price_per_unit, ''),
            nullif(cost, ''),
            nullif(cost_unit, ''),
            nullif(category, ''),
            nullif(usage_timestamp, ''),
            nullif(region, ''),
            nullif(metadata, ''),
            nullif(billing_date, ''),
            nullif(ica_execution_id, ''),
            nullif(license, ''),
            nullif(pipeline_uuid, ''),
            nullif(status, ''),
            nullif(domain, ''),
            nullif(type, ''),
            nullif(workflow_name, ''),
            nullif(workflow_version, ''),
            nullif(portal_run_id, ''),
            nullif(ref_format, ''),
            nullif(reference_raw, ''),
            nullif(ref_uuid, ''),
            nullif(id_matches_reference, '')
        ) is not null

),

hashed as (

    select
        *,
        -- Keep the legacy delimiter-free business-key contract.
        cast(
            sha2(
                coalesce(usage_id, '') || coalesce(billing_date, ''),
                256
            ) as char(64)
        ) as usage_hash
    from
        non_empty

),

differentiated as (

    select
        *
    from
        hashed
    {% if is_incremental() %}
    -- Compare only with persisted history so new in-snapshot duplicates survive.
    where not exists (
        select
            1
        from
            {{ this }} as existing
        where
            existing.usage_hash = hashed.usage_hash
    )
    {% endif %}

),

transformed as (

    select
        usage_id,
        usage_hash,
        uc_name,
        billable_account_id,
        account_name,
        account_type,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        cast(quantity as numeric(38, 20)) as quantity,
        usage_unit,
        cast(price_per_unit as numeric(25, 20)) as price_per_unit,
        cast(cost as numeric(25, 20)) as cost,
        cost_unit,
        category,
        cast(usage_timestamp as date) as usage_timestamp,
        region,
        metadata,
        cast(billing_date as date) as billing_date,
        ica_execution_id,
        license,
        pipeline_uuid,
        status,
        domain,
        type,
        workflow_name,
        workflow_version,
        portal_run_id,
        ref_format,
        reference_raw,
        ref_uuid,
        cast(id_matches_reference as boolean) as id_matches_reference,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        cast('spreadsheet__ica_usage_report' as varchar(255)) as record_source
    from
        differentiated

),

final as (

    select * from transformed

)

select * from final
