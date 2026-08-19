{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from _analysis_ data output path.
    It return single match or NULL otherwise.

    ID namespace scope specifically only to the Centre _internal_ patterns.
#}

{% macro extract_library_id(column_name) %}

    regexp_substr({{ column_name }}, '(L[0-9]{7}|L(PRJ|CCR|MDX|TGX)[0-9]{6})')

{% endmacro %}
