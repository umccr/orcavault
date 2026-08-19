{#
    Extracts the cohort/project segment immediately after 'byob-icav2/' in a file path.
    Example: byob-icav2/production/analysis/... -> 'production'

    PostgreSQL lookbehind/lookahead (?<=...) and (?=...) are not supported in Redshift.
    Uses REGEXP_SUBSTR with explicit capture group and 'e' flag instead.
#}

{% macro extract_cohort_id(column_name) %}
    nullif(
        regexp_substr(
            {{ column_name }},
            'byob-icav2/([^/]+)/',
            1,
            1,
            'e'
        ),
        ''
    )
{% endmacro %}
