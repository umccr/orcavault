{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='append_new_columns',
        full_refresh=var('ica_usage_full_refresh', false)
    )
}}

{#
    Persistent history of the Illumina detailed usage report.

    Issue: from the 2026-05 report Illumina replaced the ICA Usage Explorer with BioInsight Core, so TSA now
    holds two layouts at once.

        legacy      <= 2026-04   price_per_unit; cost_unit 'iCredits'
        bioinsight  >= 2026-05   row_seq, pricing_method, list_rate, applied_rate, cost_saved;
                                 cost_unit 'BIC' (renamed 1:1); ica_v2 + is_in_grace_period in metadata

    Resolution: carry the union. A column the other layout does not write stays null and units are stored as
    the source wrote them. Reporting folds iCredits into BIC; this model never reconciles.

    Reload policy:
      - append_new_columns compares this model's own output against the live table, never TSA against this
        model. A column added to the SQL below lands with ALTER TABLE instead of failing the run, but a
        column Glue adds to TSA that this SQL does not select is dropped silently. That is exactly how the
        seven BioInsight columns were missed; tests/assert_ica_usage_tsa_columns_captured.sql now warns.
      - full_refresh is var-gated so a project-wide --full-refresh cannot discard this history:
            dbt run -s spreadsheet__ica_usage_report --vars '{ica_usage_full_refresh: true}'
        A rebuild is lossless only while TSA still carries every source row. Verify that before rebuilding.
      - Redshift ALTER COLUMN TYPE only widens varchar, so column types are near-irreversible.

    usage_hash must never be redefined. Rows are skipped by hash equality alone, so a new definition would
    re-append the entire history.
#}

with source as (

    select
        usage_id,
        row_seq,
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
        pricing_method,
        price_per_unit,
        list_rate,
        applied_rate,
        cost,
        cost_saved,
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
        id_matches_reference,
        ica_v2,
        is_in_grace_period
    from
        {{ source('tsa', 'spreadsheet__ica_usage_report') }}

),

cleaned as (

    select
        trim(regexp_replace(usage_id,              '[\n\r]+', '')) as usage_id,
        trim(regexp_replace(row_seq,               '[\n\r]+', '')) as row_seq,
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
        trim(regexp_replace(pricing_method,        '[\n\r]+', '')) as pricing_method,
        trim(regexp_replace(price_per_unit,        '[\n\r]+', '')) as price_per_unit,
        trim(regexp_replace(list_rate,             '[\n\r]+', '')) as list_rate,
        trim(regexp_replace(applied_rate,          '[\n\r]+', '')) as applied_rate,
        trim(regexp_replace(cost,                  '[\n\r]+', '')) as cost,
        trim(regexp_replace(cost_saved,            '[\n\r]+', '')) as cost_saved,
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
        trim(regexp_replace(id_matches_reference,  '[\n\r]+', '')) as id_matches_reference,
        trim(regexp_replace(ica_v2,                '[\n\r]+', '')) as ica_v2,
        trim(regexp_replace(is_in_grace_period,    '[\n\r]+', '')) as is_in_grace_period
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
            nullif(row_seq, ''),
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
            nullif(pricing_method, ''),
            nullif(price_per_unit, ''),
            nullif(list_rate, ''),
            nullif(applied_rate, ''),
            nullif(cost, ''),
            nullif(cost_saved, ''),
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
            nullif(id_matches_reference, ''),
            nullif(ica_v2, ''),
            nullif(is_in_grace_period, '')
        ) is not null

),

hashed as (

    {#
        row_seq is deliberately out of the hash. It is always 1 today; if Illumina ever emits row_seq > 1 the
        row collides and the unique test fails, which is the intended alarm. Do not widen the hash to silence
        it, that re-appends the whole history. Confirm the new grain with the team and repair in place.
    #}

    select
        *,
        cast(
            {{ generate_hash_diff([
                'usage_id',
                'billing_date'
            ]) }} as char(64)
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
        cast(nullif(row_seq, '') as integer) as row_seq,
        uc_name,
        billable_account_id,
        account_name,
        account_type,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        cast(nullif(quantity, '') as numeric(38, 20)) as quantity,
        usage_unit,
        pricing_method,
        cast(nullif(price_per_unit, '') as numeric(25, 20)) as price_per_unit,
        cast(nullif(list_rate, '') as numeric(25, 20)) as list_rate,
        cast(nullif(applied_rate, '') as numeric(25, 20)) as applied_rate,
        cast(nullif(cost, '') as numeric(25, 20)) as cost,
        cast(nullif(cost_saved, '') as numeric(25, 20)) as cost_saved,
        cost_unit,
        category,
        cast(nullif(usage_timestamp, '') as date) as usage_timestamp,
        region,
        metadata,
        cast(nullif(billing_date, '') as date) as billing_date,
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
        -- Redshift cannot cast varchar 'true'/'false' straight to boolean, see the macro.
        {{ cast_varchar_to_boolean('id_matches_reference') }} as id_matches_reference,
        {{ cast_varchar_to_boolean('ica_v2') }} as ica_v2,
        {{ cast_varchar_to_boolean('is_in_grace_period') }} as is_in_grace_period,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        cast('spreadsheet__ica_usage_report' as varchar(255)) as record_source
    from
        differentiated

),

final as (

    select * from transformed

)

select * from final
