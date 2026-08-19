{#
    Extracts and returns the sequencing run date from a sequencing_run_id.

    Two instrument patterns supported:
        NovaSeq6000: YYMMDD_A00000_0000_AAAAAAAAAA  -> 6-digit date, cast via 'YYMMDD'
        NovaSeqX:    YYYYMMDD_LH00000_0000_AAAAAAAAAA -> 8-digit date, cast via 'YYYYMMDD'
#}

{% macro extract_sequencing_run_date(column_name) %}
    case
        when regexp_substr({{ column_name }}, '^[0-9]{8}_LH[0-9]{5}_[0-9]{4}_[A-Z0-9]{10}') != ''
            then to_date(
                regexp_substr({{ column_name }}, '^[0-9]{8}'),
                'YYYYMMDD'
            )
        when regexp_substr({{ column_name }}, '^[0-9]{6}_A[0-9]{5}_[0-9]{4}_[A-Z0-9]{10}') != ''
            then to_date(
                regexp_substr({{ column_name }}, '^[0-9]{6}'),
                'YYMMDD'
            )
        else null
    end
{% endmacro %}
