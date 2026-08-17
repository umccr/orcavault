{#
    Extracts a file extension from the right of a filename using 1-based right offset.
    Redshift SPLIT_PART does not support negative indexing unlike PostgreSQL.

    Returns NULL if the result is an empty string or if the offset exceeds the number
    of actual parts in the string.

    Usage:
        {{ split_part_from_right('filename', '.', 1) }}  -- last part
        {{ split_part_from_right('filename', '.', 2) }}  -- second to last
        {{ split_part_from_right('filename', '.', 3) }}  -- third to last
        {{ split_part_from_right('filename', '.', 4) }}  -- fourth to last
#}

{% macro split_part_from_right(column_name, delimiter, offset) %}
    nullif(
        case
            when regexp_count({{ column_name }}, '\\{{ delimiter }}') + 1 - ({{ offset }} - 1) < 1
                then ''
            else
                split_part(
                    {{ column_name }},
                    '{{ delimiter }}',
                    regexp_count({{ column_name }}, '\\{{ delimiter }}') + 1 - ({{ offset }} - 1)
                )
        end,
        ''
    )
{% endmacro %}
