{% macro cdc_fill_delete(column, key='orcabus_id') -%}
    {#-

    DMS writes a delete as a row with `op = 'D'` that only has the table's primary key. This macro fills in the rest
    of the columns by fetching the previous row that isn't a delete. `key` has to be the table's primary key. Currently
    this isn't a performance burden as the only user is the SRM which does lookback for other data anyway. This approach
    should be revisited if upstream ever sets `replica identity full`, which would mean that the fill in wouldn't be
    required.

    -#}
    case
        when op = 'D' then lag({{ column }}) ignore nulls over (
            partition by {{ key }}
            order by _dms_cdc_timestamp, case when op = 'D' then 1 else 0 end
        )
        else {{ column }}
    end
{%- endmacro %}
