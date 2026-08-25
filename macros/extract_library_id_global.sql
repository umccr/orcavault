{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from the path more globally.

    Extracts all matching library IDs from a file path column using known patterns.
    In PostgreSQL, this uses regexp_matches() function i.e. explode the record and return all matching as multiple rows.
    This macros implementation mimic PostgreSQL regexp_matches() with 'g' flag which is not supported in Redshift.

    Redshift REGEXP_SUBSTR with occurrence index (via cross join numbers CTE) is used instead.
    The numbers CTE must be present in the calling model, generated via {{ generate_series(n) }}.

    Example:
    See models/dcl/business_vault/s3object/sat_s3object_by_library.sql

    Supported patterns:
        - L0000000        (7 digits)
        - LPRJ000000      (6 digits)
        - LCCR000000      (6 digits)
        - LMDX000000      (6 digits)
        - LTGX000000      (6 digits)
        - Undetermined
        - CPCT00000000*   (8 digits + optional suffix)
        - DRUP00000000*   (8 digits + optional suffix)
        - CORE00000000*   (8 digits + optional suffix)
        - ACTN00000000*   (8 digits + optional suffix)
        - WIDE00000000*   (8 digits + optional suffix)
        - GAYA00000000*   (8 digits + optional suffix)
        - GARV_0000_*     (4 digits + optional suffix)
        - ICGC_0000_*     (4 digits + optional suffix)

    Usage:
        -- In the model, first include the numbers CTE:
        numbers as ( {{ generate_series(10) }} ),

        -- Then in your select:
        {{ extract_library_id_global('column_name') }} as library_id

    Baseline:
        '(L[0-9]{7}|L(PRJ|CCR|MDX|TGX)[0-9]{6}|Undetermined)',
#}

{% macro extract_library_id_global(column_name) %}
    nullif(
        regexp_substr(
            {{ column_name }},
            '(L[0-9]{7}|LPRJ[0-9]{6}|LCCR[0-9]{6}|LMDX[0-9]{6}|LTGX[0-9]{6}|Undetermined|(CPCT|DRUP|CORE|ACTN|WIDE|GAYA)[0-9]{8}[A-Z0-9]*|(GARV|ICGC)_[0-9]{4}(_T|_N)?)',
            1,
            numbers.idx
        ),
        ''
    )
{% endmacro %}
