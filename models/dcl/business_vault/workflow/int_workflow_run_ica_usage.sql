{{
    config(
        materialized='table',
        dist='workflow_run_hk',
        sort=['workflow_run_hk', 'billing_date']
    )
}}

{#
    Reconciles the two Illumina usage export layouts into one comparable grain for the marts.
    See doc string at models/dcl/business_vault/workflow/_int.yml

    Rebuilt from sat_workflow_run_ica_usage on every run, so the business rules below can change freely
    without touching the append-only PSA and satellite:

      - Units: the unit the source wrote is kept as source_cost_unit and source_usage_unit. The reported
        cost_unit and usage_unit, and every amount, are derived from it through the mdm__ica_billing_unit
        seed, which today maps iCredits to BIC at the 1:1 rate Illumina applied at the 2026-05 cutover. The
        rate used is recorded next to the amounts. A unit the seed does not know passes through unchanged
        with a null conversion rate, so it stays visible as its own unit in the marts instead of being merged
        into BIC or dropped.
      - Rates: the legacy price_per_unit was renamed list_rate. No discount existed before the cutover
        (quantity * price_per_unit reproduced cost to rounding), so it also stands in for applied_rate.
      - cost_saved: null before the cutover means no discount, hence 0.
      - pricing_method stays null for legacy rows. The source never reported it and inventing a value would
        misstate the record.

    Numeric typing: Redshift multiplication yields precision p1 + p2 + 1 and scale s1 + s2, and fails once
    that leaves 128-bit range. The operands are narrowed first so every product fits in 38 digits without
    relying on implicit capping: the conversion rate is numeric(9, 6), usage_quantity is taken at
    numeric(28, 10), which keeps all 18 integer digits of numeric(38, 20) and the ten decimals the source
    writes, and cost and the rates multiply as numeric(25, 20).
#}

with usage as (

    select * from {{ ref('sat_workflow_run_ica_usage') }}

),

billing_unit as (

    select
        source_unit,
        target_unit,
        cast(conversion_rate as numeric(9, 6)) as conversion_rate
    from {{ ref('mdm__ica_billing_unit') }}

),

joined as (

    {# Attach the unit mapping for the cost side and the usage side independently. #}

    select
        usage.*,
        cost_map.target_unit                                            as cost_target_unit,
        cost_map.conversion_rate                                        as cost_conversion_rate,
        coalesce(cost_map.conversion_rate, cast(1 as numeric(9, 6)))    as cost_rate,
        usage_map.target_unit                                           as usage_target_unit,
        usage_map.conversion_rate                                       as usage_conversion_rate,
        coalesce(usage_map.conversion_rate, cast(1 as numeric(9, 6)))   as usage_rate
    from usage
        left join billing_unit as cost_map
            on cost_map.source_unit = usage.cost_unit
        left join billing_unit as usage_map
            on usage_map.source_unit = usage.usage_unit

),

reconciled as (

    select
        workflow_run_hk,
        usage_hash,
        usage_id,
        row_seq,
        {#
          Mirrors detect_source_layout() in the Glue job: BioInsight Core is recognised by the columns only it
          writes, legacy by price_per_unit. A row carrying neither is left null.
        #}
        case
            when row_seq is not null or list_rate is not null or applied_rate is not null then 'bioinsight'
            when price_per_unit is not null then 'legacy'
            else null
        end                                                             as source_layout,
        usage_context,
        usage_context_type,
        user_name,
        product,
        usage_type_description,
        category,
        region,
        usage_timestamp,
        billing_date,
        ica_execution_id,
        is_license_cost,
        id_matches_reference,
        ica_v2,
        is_in_grace_period,
        pricing_method,
        usage_unit                                                      as source_usage_unit,
        coalesce(usage_target_unit, usage_unit)                         as usage_unit,
        usage_conversion_rate,
        cast(usage_quantity as numeric(28, 10)) * usage_rate            as usage_quantity,
        cost_unit                                                       as source_cost_unit,
        coalesce(cost_target_unit, cost_unit)                           as cost_unit,
        cost_conversion_rate,
        coalesce(list_rate, price_per_unit) * cost_rate                 as list_rate,
        coalesce(applied_rate, price_per_unit) * cost_rate              as applied_rate,
        cost * cost_rate                                                as cost,
        coalesce(cost_saved, cast(0 as numeric(25, 20))) * cost_rate    as cost_saved
    from joined

),

final as (

    select
        cast(workflow_run_hk        as char(64))        as workflow_run_hk,
        cast(usage_hash             as char(64))        as usage_hash,
        cast(usage_id               as varchar(255))    as usage_id,
        cast(row_seq                as integer)         as row_seq,
        cast(source_layout          as varchar(20))     as source_layout,
        cast(usage_context          as varchar(255))    as usage_context,
        cast(usage_context_type     as varchar(255))    as usage_context_type,
        cast(user_name              as varchar(255))    as user_name,
        cast(product                as varchar(255))    as product,
        cast(usage_type_description as varchar(255))    as usage_type_description,
        cast(category               as varchar(255))    as category,
        cast(region                 as varchar(255))    as region,
        cast(usage_timestamp        as date)            as usage_timestamp,
        cast(billing_date           as date)            as billing_date,
        cast(ica_execution_id       as varchar(255))    as ica_execution_id,
        cast(is_license_cost        as boolean)         as is_license_cost,
        cast(id_matches_reference   as boolean)         as id_matches_reference,
        cast(ica_v2                 as boolean)         as ica_v2,
        cast(is_in_grace_period     as boolean)         as is_in_grace_period,
        cast(pricing_method         as varchar(255))    as pricing_method,
        cast(source_usage_unit      as varchar(255))    as source_usage_unit,
        cast(usage_unit             as varchar(255))    as usage_unit,
        cast(usage_conversion_rate  as numeric(9, 6))   as usage_conversion_rate,
        cast(usage_quantity         as numeric(38, 20)) as usage_quantity,
        cast(source_cost_unit       as varchar(255))    as source_cost_unit,
        cast(cost_unit              as varchar(255))    as cost_unit,
        cast(cost_conversion_rate   as numeric(9, 6))   as cost_conversion_rate,
        cast(list_rate              as numeric(25, 20)) as list_rate,
        cast(applied_rate           as numeric(25, 20)) as applied_rate,
        cast(cost                   as numeric(25, 20)) as cost,
        cast(cost_saved             as numeric(25, 20)) as cost_saved
    from reconciled

)

select * from final
