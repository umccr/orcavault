{#
    Extracts a portal_run_id from a file path column.
    Pattern: 8 digits followed by 8 alphanumeric characters, surrounded by slashes.
    Example: /20241122d876a770/

    See:
        https://github.com/umccr/data-portal-apis/blob/main/docs/pipeline/portal_run_id.md
        https://github.com/OrcaBus/wiki/blob/caeded4/orcabus/glossary.md

    Non-capturing groups (?:...) are not supported in Redshift regex engine.
    Uses plain grouping and REGEXP_SUBSTR, mimic to PostgreSQL regexp_match() effect.
#}

{% macro extract_portal_run_id(column_name) %}
    nullif(
        regexp_substr(
            {{ column_name }},
            '/([0-9]{8}[a-zA-Z0-9]{8})/',
            1,
            1,
            'e'
        ),
        ''
    )
{% endmacro %}
