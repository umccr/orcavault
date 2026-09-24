{% test cdc_partition_date_valid(model, column_name) %}

{#-

Checks whether the DMS partition date is valid. It should either be at the
table root, e.g. `.../<table>/LOAD00000001.parquet`, or under a `.../YYYY/MM/DD/`
folder. It should also never be dated into the future.

-#}

with staged as (
    select
        source_file_path,
        {{ column_name }},
        regexp_instr(source_file_path, '/[0-9]{4}/[0-9]{2}/[0-9]{2}/[^/]+$') > 0 as has_date_folder
    from {{ model }}
)

select *
from staged
where (has_date_folder and {{ column_name }} is null)
   or (not has_date_folder and {{ column_name }} is not null)
   or {{ column_name }} > current_date + 1

{% endtest %}
