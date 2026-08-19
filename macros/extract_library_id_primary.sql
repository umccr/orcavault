{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from _primary data_ output path.
    It return single match or NULL otherwise. Include the 'Undetermined' as expected for typical bcl_convert output.

    ID namespace scope specifically only to the Centre _internal_ patterns.

    Extracts a single matching library_id from a file path column.
    Returns single match or NULL otherwise.
    Includes 'Undetermined' as expected for typical bcl_convert output.

    Non-capturing groups (?:...) are not supported in Redshift regex engine.
#}

{% macro extract_library_id_primary(column_name) %}
    nullif(
        regexp_substr(
            {{ column_name }},
            '(L[0-9]{7}|LPRJ[0-9]{6}|LCCR[0-9]{6}|LMDX[0-9]{6}|LTGX[0-9]{6}|Undetermined)',
            1,
            1
        ),
        ''
    )
{% endmacro %}
