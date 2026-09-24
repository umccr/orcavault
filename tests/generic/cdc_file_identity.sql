{% test cdc_file_identity(model) %}

{#-

This determines whether a source file is ingested only once. It tests that the file
as been staged into one partition, and that it has been loaded only once. Both of
these conditions would be incorrect behaviour and would fail the test.

-#}

select
    source_file_path
from {{ model }}
group by source_file_path
having count(distinct load_datetime) > 1
    or count(distinct source_partition_date) > 1

{% endtest %}
