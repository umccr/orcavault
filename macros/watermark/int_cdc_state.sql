{% macro int_cdc_state(source_name, table_name, partition_by='orcabus_id', order_by=[]) %}
    {#-

    This is the macro that creates the intermediate CDC state models from the DMS source. It is
    the latest row for each key up to the run's pending value. It carries forward the cdc window
    flag that downstream models base their logic on.

    This is required because it determines how any downstream model changes based on it's input.
    In can't be a simple filter because a lot of models have multiple inputs that each need to
    consider this value. A join also needs unchanged rows, e.g. a new link between an unchanged
    library and a project would find nothing without the `cdc_changed`, as this row changes when
    any of the inputs do.

    -#}

    {% do config(materialized='ephemeral') %}

    select * from (
        select
            *,
            row_number() over (
                partition by {{ partition_by }}
                order by _dms_cdc_timestamp desc
                    {%- for column in order_by %}
                        , {{ column }} desc
                    {% endfor %}
            ) as rn,
            {{ cdc_window(source_name, table_name) }} as cdc_changed
        from {{ source(source_name, table_name) }}
        where {{ cdc_upper_bound(source_name, table_name) }}
    ) t
    where rn = 1
{% endmacro %}
