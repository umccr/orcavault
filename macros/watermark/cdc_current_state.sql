{% macro cdc_current_state_order(order_by=[]) -%}
    {#-

        Configures the ordering of a current row according to `_dms_cdc_timestamp` followed
        by the `order_by` input list.

    -#}

    _dms_cdc_timestamp desc,
    {%- for column in order_by %}
    {{ column }} desc,
    {%- endfor %}
    load_datetime desc,
    source_file_path desc
{%- endmacro %}


{% macro cdc_current_state(psa_model, partition_by='orcabus_id', order_by=[]) %}
    {#-

        This creates the CDC current state intermediate state from the PSA relations. The reason
        this is a separate macro and exists in the first place is so that the logic that determines
        which row is needed to be ingested is well-defined early on in the warehouse run.

        This macro defines the order, which prefers the `_dms_cdc_timestamp` followed by any custom
        `order_by` columns, which is needed for historical tables. The `load_datetime` and `source_file_path`
        is further added to ensure that files are ordered deterministically.

    -#}

    {% do config(materialized='ephemeral') %}

    select * from (
        select
            *,
            row_number() over (
                partition by {{ partition_by }}
                order by {{ cdc_current_state_order(order_by) }}
            ) as rn
        from {{ ref(psa_model) }}
    ) t
    where rn = 1
{% endmacro %}
