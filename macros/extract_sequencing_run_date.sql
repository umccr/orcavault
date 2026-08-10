{% macro extract_sequencing_run_date(column_name) %}

    case
        when len(regexp_substr({{ column_name }}, '^([0-9]{6}|[0-9]{8})')) = 6
            then to_date(regexp_substr({{ column_name }}, '^([0-9]{6}|[0-9]{8})'), 'YYMMDD')
        else to_date(regexp_substr({{ column_name }}, '^([0-9]{6}|[0-9]{8})'), 'YYYYMMDD')
    end

{% endmacro %}
