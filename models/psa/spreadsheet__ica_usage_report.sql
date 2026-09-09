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

    Illumina replaced the ICA Usage Explorer with the BioInsight Core Usage Explorer from the 2026-05 report
    onwards, so the TSA table carries the union of two source layouts side by side:

        Legacy (2026-04 and earlier)    BioInsight Core (2026-05 onwards)
        ----------------------------    ---------------------------------
        (none)                          row_seq             always 1 so far
        price_per_unit                  list_rate           renamed, identical values
        (none)                          applied_rate        rate actually charged, after discount
        (none)                          pricing_method      "Standard Rate" so far
        (none)                          cost_saved          quantity * (list_rate - applied_rate)
        cost_unit "iCredits"            cost_unit "BIC"     renamed 1:1, values unchanged
        (none)                          ica_v2              parsed from storage row metadata
        (none)                          is_in_grace_period  parsed from storage row metadata

    This model stays a faithful mirror of the source. A column the other layout does not carry is null and
    the units are stored exactly as written. The two eras are reconciled downstream in
    dcl.int_workflow_run_ica_usage, never here.

    Reload policy:

      - on_schema_change='append_new_columns' adds a new column with ALTER TABLE, leaves it null on the rows
        already loaded and never drops a column. This is what stops a Glue-side column addition from failing
        the run, and it is the normal path for every future source change.
      - full_refresh defaults to false, so a project-wide `dbt run --full-refresh` cannot silently discard
        this history. Rebuild deliberately, naming the model, when that is what you mean:

            dbt run -s spreadsheet__ica_usage_report --vars '{ica_usage_full_refresh: true}'

      - A rebuild is lossless only while TSA still carries every source row. Glue truncates and reloads TSA
        from all CSVs under the source prefix on each run, so that holds today. It stops holding the moment a
        source CSV is removed from the bucket or Illumina restates a past month; from then on this table is
        the only record and a rebuild would silently drop rows. Check before rebuilding:

            select count(*) from psa.spreadsheet__ica_usage_report p
            where not exists (select 1 from <tsa hashed> t where t.usage_hash = p.usage_hash)

      - Column types are near-irreversible on Redshift (ALTER COLUMN TYPE only widens varchar), so choose
        them carefully the first time.

    usage_hash is the append-only dedupe key and must never be redefined. Rows already loaded are skipped by
    hash equality alone, so a new hash definition would re-append the entire history on the next run.
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
        (usage_id, billing_date) has been unique in every report to date because row_seq is always 1.
        row_seq is deliberately left out of the hash: if Illumina ever emits row_seq > 1 the second row
        collides on usage_hash and the unique test on this model fails, which is the intended alarm that
        the source grain has changed. Do not widen the hash to silence it, the whole history would
        re-append. Confirm the new grain with the team and repair in place instead.
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
