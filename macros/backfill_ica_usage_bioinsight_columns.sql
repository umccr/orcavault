{#
    One-off, idempotent backfill of the BioInsight Core columns on the append-only ICA usage models.

    Why:
    The BioInsight Core layout (2026-05 onwards) reached tsa.spreadsheet__ica_usage_report before the PSA and
    DCL models knew its columns, so rows already appended for those billing months carry null in row_seq,
    pricing_method, list_rate, applied_rate, cost_saved, ica_v2 and is_in_grace_period. Both models dedupe on
    usage_hash, so those rows will never be re-appended and the only repair is an in-place UPDATE.

    What it does:
      1. psa.spreadsheet__ica_usage_report <- tsa.spreadsheet__ica_usage_report, joined on the usage_hash the
         PSA model derives (cleaned usage_id + billing_date) and applying the same casts.
      2. dcl.sat_workflow_run_ica_usage <- psa.spreadsheet__ica_usage_report, joined on usage_hash.
    Only rows whose target columns are all null and whose source carries a BioInsight value are touched, so
    re-running is a no-op. The satellite hash_diff is left as loaded.

    Prerequisite: the columns must already exist on both models, i.e. run them once so append_new_columns
    adds the columns (zero rows append because every usage_hash is already present).

    Usage:
        dbt run -s spreadsheet__ica_usage_report sat_workflow_run_ica_usage
        dbt run-operation backfill_ica_usage_bioinsight_columns                         # dry run, counts only
        dbt run-operation backfill_ica_usage_bioinsight_columns --args '{dry_run: false}'
        dbt run -s int_workflow_run_ica_usage+
#}

{% macro backfill_ica_usage_bioinsight_columns(dry_run=true) %}

    {%- set tsa = source('tsa', 'spreadsheet__ica_usage_report') -%}
    {%- set psa = ref('spreadsheet__ica_usage_report') -%}
    {%- set sat = ref('sat_workflow_run_ica_usage') -%}
    {%- set new_columns = [
        'row_seq', 'pricing_method', 'list_rate', 'applied_rate', 'cost_saved', 'ica_v2', 'is_in_grace_period'
    ] -%}

    {# Prerequisite: refuse to run until append_new_columns has added the columns to both targets. #}
    {%- for relation in [psa, sat] -%}
        {%- set present = adapter.get_columns_in_relation(relation) | map(attribute='name') | list -%}
        {%- for column in new_columns -%}
            {%- if column not in present -%}
                {{ exceptions.raise_compiler_error(
                    relation ~ " has no column " ~ column
                    ~ ". Run the model first so append_new_columns adds it: dbt run -s " ~ relation.identifier
                ) }}
            {%- endif -%}
        {%- endfor -%}
    {%- endfor -%}

    {#- Step 1 source: TSA rows in the BioInsight layout, cleaned and typed exactly as the PSA model does. -#}
    {%- set psa_source -%}
        select
            cast({{ generate_hash_diff(['usage_id', 'billing_date']) }} as char(64)) as usage_hash,
            cast(row_seq as integer)                                                 as row_seq,
            pricing_method,
            cast(list_rate as numeric(25, 20))                                       as list_rate,
            cast(applied_rate as numeric(25, 20))                                    as applied_rate,
            cast(cost_saved as numeric(25, 20))                                      as cost_saved,
            {{ cast_varchar_to_boolean('ica_v2') }}                                  as ica_v2,
            {{ cast_varchar_to_boolean('is_in_grace_period') }}                      as is_in_grace_period
        from (
            select
                trim(regexp_replace(usage_id,                   '[\n\r]+', ''))      as usage_id,
                trim(regexp_replace(billing_date,               '[\n\r]+', ''))      as billing_date,
                nullif(trim(regexp_replace(row_seq,            '[\n\r]+', '')), '') as row_seq,
                nullif(trim(regexp_replace(pricing_method,     '[\n\r]+', '')), '') as pricing_method,
                nullif(trim(regexp_replace(list_rate,          '[\n\r]+', '')), '') as list_rate,
                nullif(trim(regexp_replace(applied_rate,       '[\n\r]+', '')), '') as applied_rate,
                nullif(trim(regexp_replace(cost_saved,         '[\n\r]+', '')), '') as cost_saved,
                nullif(trim(regexp_replace(ica_v2,             '[\n\r]+', '')), '') as ica_v2,
                nullif(trim(regexp_replace(is_in_grace_period, '[\n\r]+', '')), '') as is_in_grace_period
            from {{ tsa }}
        ) as cleaned
        where row_seq is not null or list_rate is not null or applied_rate is not null
    {%- endset -%}

    {%- set psa_pending -%}
        select count(*) as pending
        from {{ psa }} as target
            join ({{ psa_source }}) as src on src.usage_hash = target.usage_hash
        where target.row_seq is null and target.list_rate is null and target.applied_rate is null
    {%- endset -%}

    {%- set psa_update -%}
        update {{ psa }} as target
        set
            row_seq            = src.row_seq,
            pricing_method     = src.pricing_method,
            list_rate          = src.list_rate,
            applied_rate       = src.applied_rate,
            cost_saved         = src.cost_saved,
            ica_v2             = src.ica_v2,
            is_in_grace_period = src.is_in_grace_period
        from ({{ psa_source }}) as src
        where src.usage_hash = target.usage_hash
          and target.row_seq is null and target.list_rate is null and target.applied_rate is null
    {%- endset -%}

    {#- Step 2: satellite from the (now complete) PSA. -#}
    {%- set sat_predicate -%}
        src.usage_hash = target.usage_hash
          and target.row_seq is null and target.list_rate is null and target.applied_rate is null
          and (src.row_seq is not null or src.list_rate is not null or src.applied_rate is not null)
    {%- endset -%}

    {%- set sat_pending -%}
        select count(*) as pending
        from {{ sat }} as target
            join {{ psa }} as src on {{ sat_predicate }}
    {%- endset -%}

    {%- set sat_update -%}
        update {{ sat }} as target
        set
            row_seq            = src.row_seq,
            pricing_method     = src.pricing_method,
            list_rate          = src.list_rate,
            applied_rate       = src.applied_rate,
            cost_saved         = src.cost_saved,
            ica_v2             = src.ica_v2,
            is_in_grace_period = src.is_in_grace_period
        from {{ psa }} as src
        where {{ sat_predicate }}
    {%- endset -%}

    {%- if dry_run -%}

        {%- set psa_count = run_query(psa_pending).columns[0].values()[0] -%}
        {{ log("[dry run] " ~ psa ~ ": " ~ psa_count ~ " rows pending backfill from TSA", info=true) }}
        {%- set sat_count = run_query(sat_pending).columns[0].values()[0] -%}
        {{ log("[dry run] " ~ sat ~ ": " ~ sat_count ~ " rows pending backfill from PSA (before the PSA step)", info=true) }}
        {{ log("Re-run with --args '{dry_run: false}' to apply.", info=true) }}

    {%- else -%}

        {%- call statement('psa_backfill', fetch_result=false, auto_begin=true) -%}
            {{ psa_update }}
        {%- endcall -%}
        {{ log(psa ~ ": " ~ load_result('psa_backfill')['response'].rows_affected ~ " rows backfilled from TSA", info=true) }}

        {%- call statement('sat_backfill', fetch_result=false, auto_begin=true) -%}
            {{ sat_update }}
        {%- endcall -%}
        {{ log(sat ~ ": " ~ load_result('sat_backfill')['response'].rows_affected ~ " rows backfilled from PSA", info=true) }}

        {%- do adapter.commit() -%}
        {{ log("Committed. Now rebuild the derived models: dbt run -s int_workflow_run_ica_usage+", info=true) }}

    {%- endif -%}

{% endmacro %}
