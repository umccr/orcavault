{#
    Generates a static zero-cost in-memory tally table as a CTE-ready UNION ALL series.
    Redshift has no native generate_series() function, so this macro compiles down to
    a static UNION ALL block at dbt compile time — zero runtime cost.

    Usage:
        {{ generate_series(10) }}

    Compiles to:
        select 1 as idx union all
        select 2 as idx union all
        ...
        select 10 as idx
#}

{% macro generate_series(upper_bound) %}
    {% for i in range(1, upper_bound + 1) %}
    select {{ i }} as idx {% if not loop.last %} union all {% endif %}
    {% endfor %}
{% endmacro %}
