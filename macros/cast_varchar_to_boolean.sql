{#

In Amazon Redshift, you cannot directly cast a VARCHAR column to a BOOLEAN if the column contains full string
words like 'true', 'false', 'yes', or 'no'. Running my_string_col::boolean triggers the cannot cast type character
varying to boolean compilation error.

Redshift only allows a direct string-to-boolean cast if the literal values are already encoded as single characters or
digits (such as 't', 'f', '1', or '0').

To safely convert a standard VARCHAR text column to a true BOOLEAN in Redshift, you must use a explicit CASE expression.

#}

{% macro cast_varchar_to_boolean(column_name) %}

    case
        when lower(cast({{ column_name }} as varchar)) in ('true', 't', 'yes', 'y', '1', 'on') then true
        when lower(cast({{ column_name }} as varchar)) in ('false', 'f', 'no', 'n', '0', 'off') then false
        else null
    end

{% endmacro %}
