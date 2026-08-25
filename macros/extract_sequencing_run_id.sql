{#
    Extracts a sequencing_run_id from a file path column.
    Pattern: (6 or 8 digits)_(A00000 or LH00000)_0000_AAAAAAAAAA, surrounded by slashes.
    Example:
        NovaSeq 6000 - /351128_A00000_0091_AAAAACCCTG/
        NovaSeq X    - /30251124_LH00000_0001_AAAAACCCTG/

    See:
        https://www.google.com/search?q=illumina+instrument+run+id
        https://knowledge.illumina.com/instrumentation/general/instrumentation-general-reference_material-list/000006351

    Non-capturing groups (?:...) are not supported in Redshift regex engine.
    Uses plain grouping and REGEXP_SUBSTR, mimic to PostgreSQL regexp_match() effect.
#}

{% macro extract_sequencing_run_id(column_name) %}
    nullif(
        regexp_substr(
            {{ column_name }},
            '/([0-9]{6}_A[0-9]{5}_[0-9]{4}_[A-Z0-9]{10}|[0-9]{8}_LH[0-9]{5}_[0-9]{4}_[A-Z0-9]{10})/',
            1,
            1,
            'e'
        ),
        ''
    )
{% endmacro %}
